#include <linux/init.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/ioctl.h>
#include <asm/uaccess.h>   /* copy_to_user */
#include <asm/io.h>
#include <linux/cdev.h>
#include <linux/sched.h>
#include <linux/dma-mapping.h>
#include <mach/memory.h>
#include <mach/hardware.h>
#include <mach/irqs.h>
#include <mach/edma.h>
#include <linux/gpio.h>

#include "hw_cm_per.h"
#include "hw_gpmc.h"
#include "soc_AM335x.h"


#define INTERRUPT_GPIO1 74

#define CS_ON	0
#define CS_OFF	5
#define ADV_ON	0
#define ADV_OFF	2
#define WR_CYC	5
#define WR_ON	3
#define WR_OFF 5
#define RD_CYC	5
#define OE_ON	3
#define OE_OFF 5
#define RD_ACC_TIME 5
#define WRDATAONADMUX 3  //number of cycle before taking control of data bus (when add/data multiplexing)


//       <--4-->
//CS1	\_______/
//	<-1>_____
//ADV	\__/
//	____ <-2->
//WR	     \___/
//	____ <-2->
//WR	     \___/





/* Use 'p' as magic number */
#define LOGIBONE_FIFO_IOC_MAGIC 'p'
/* Please use a different 8-bit number in your code */
#define LOGIBONE_FIFO_RESET _IO(LOGIBONE_FIFO_IOC_MAGIC, 0)


#define LOGIBONE_FIFO_PEEK _IOR(LOGIBONE_FIFO_IOC_MAGIC, 1, short)
#define LOGIBONE_FIFO_NB_FREE _IOR(LOGIBONE_FIFO_IOC_MAGIC, 2, short)
#define LOGIBONE_FIFO_NB_AVAILABLE _IOR(LOGIBONE_FIFO_IOC_MAGIC, 3, short)
#define LOGIBONE_FIFO_MODE _IO(LOGIBONE_FIFO_IOC_MAGIC, 4)
#define LOGIBONE_DIRECT_MODE _IO(LOGIBONE_FIFO_IOC_MAGIC, 5)


//writing to fifo A reading from fifo B

#define FPGA_BASE_ADDR	 0x09000000
#define FIFO_BASE_ADDR	 0x00000000
#define FIFO_CMD_OFFSET  0x0400
#define FIFO_SIZE_OFFSET	(FIFO_CMD_OFFSET)
#define FIFO_NB_AVAILABLE_A_OFFSET	(FIFO_CMD_OFFSET + 1)
#define FIFO_NB_AVAILABLE_B_OFFSET	(FIFO_CMD_OFFSET + 2)
#define FIFO_PEEK_OFFSET	(FIFO_CMD_OFFSET + 3)
#define FIFO_READ_OFFSET	0
#define FIFO_WRITE_OFFSET	0
#define FIFO_BLOCK_SIZE	1024  //512 * 16 bits

#define INTERRUPT_MANAGER_BASE_ADDR FPGA_BASE_ADDR+0x0800
#define INTERRUPT_MANAGER_INT1_OFFSET	0x0002
#define INTERRUPT_MANAGER_INT2_OFFSET	0x0004
#define INTERRUPT_MANAGER_INT3_OFFSET	0x0006



char * gDrvrName = "LOGIBONE_fifo";
unsigned char gDrvrMajor = 246 ;
unsigned char gDrvrMinor = 0 ;
unsigned char nbDevices  = 1 ;

volatile unsigned short * gpmc_cs1_pointer ;
volatile unsigned short * gpmc_cs1_virt ;

int dma_ch ;
dma_addr_t dmaphysbuf = 0;
dma_addr_t dmapGpmcbuf = 0x09000000;
static volatile int irqraised1 = 0;

unsigned char * readBuffer ;
unsigned char * writeBuffer ;

int pinIrqLine ;


#define BUFFER_SIZE 2048 



int setupGPMCClock(void) ;
int setupGPMCNonMuxed(void) ;
unsigned short int getNbFree(void);
unsigned short int getNbAvailable(void);
int edma_memtomemcpy(int count, unsigned long src_addr, unsigned long trgt_addr,int event_queue,  enum address_mode mode);
static void dma_callback(unsigned lch, u16 ch_status, void *data);
irqreturn_t gpio_interrupt_1(int irq, void *dev_id, struct pt_regs *regs);


enum LOGIBONE_fifo_read_mode{
	fifo,
	direct
} read_mode;

unsigned int fifo_size ;


void orShortRegister(unsigned short int value, volatile unsigned int * port){
	unsigned short oldVal ;
	oldVal = ioread32(port);
	iowrite32(oldVal | value, port);
}

int setupGPMCClock(void){
	volatile unsigned int * prcm_reg_pointer ;
	printk("Configuring Clock for GPMC \n");  
	if (check_mem_region(SOC_PRCM_REGS + CM_PER_GPMC_CLKCTRL/4, 4)) {
	    printk("%s: memory already in use\n", gDrvrName);
	    return -EBUSY;
	}
	request_mem_region(SOC_PRCM_REGS + CM_PER_GPMC_CLKCTRL, 4, gDrvrName);
	

	prcm_reg_pointer = ioremap_nocache(SOC_PRCM_REGS + CM_PER_GPMC_CLKCTRL, sizeof(int));
	//enable clock to GPMC module
	
	orShortRegister(CM_PER_GPMC_CLKCTRL_MODULEMODE_ENABLE, prcm_reg_pointer);
	//check to see if enabled
	printk("CM_PER_GPMC_CLKCTRL value :%x \n",ioread32(prcm_reg_pointer)); 
	while((ioread32(prcm_reg_pointer) & 
	CM_PER_GPMC_CLKCTRL_IDLEST) != (CM_PER_GPMC_CLKCTRL_IDLEST_FUNC << CM_PER_GPMC_CLKCTRL_IDLEST_SHIFT));
	printk("GPMC clock is running \n");
	iounmap(prcm_reg_pointer);
	release_mem_region(SOC_PRCM_REGS + CM_PER_GPMC_CLKCTRL/4, 4);

	return 1;
}

int setupGPMCNonMuxed(void){
	unsigned int temp = 0;
	unsigned short int csNum = 1 ;	
	volatile unsigned int * gpmc_reg_pointer ;

	printk("Configuring GPMC for non muxed access \n");	


	if (check_mem_region(SOC_GPMC_0_REGS, 720)) {
	    printk("%s: memory already in use\n", gDrvrName);
	    return -EBUSY;
	}
	request_mem_region(SOC_GPMC_0_REGS, 720, gDrvrName);
	gpmc_reg_pointer = ioremap_nocache(SOC_GPMC_0_REGS,  720);



	printk("GPMC_REVISION value :%x \n", ioread32(gpmc_reg_pointer + GPMC_REVISION/4)); 
	
	orShortRegister(GPMC_SYSCONFIG_SOFTRESET, gpmc_reg_pointer + GPMC_SYSCONFIG/4 ) ;
	printk("Trying to reset GPMC \n"); 
	printk("GPMC_SYSSTATUS value :%x \n", ioread32(gpmc_reg_pointer + GPMC_SYSSTATUS/4)); 
	while((ioread32(gpmc_reg_pointer + GPMC_SYSSTATUS/4) & 
		GPMC_SYSSTATUS_RESETDONE) == GPMC_SYSSTATUS_RESETDONE_RSTONGOING){
		printk("GPMC_SYSSTATUS value :%x \n", ioread32(gpmc_reg_pointer + 
		GPMC_SYSSTATUS/4));
	}
	printk("GPMC reset \n");
	temp = ioread32(gpmc_reg_pointer + GPMC_SYSCONFIG/4);
	temp &= ~GPMC_SYSCONFIG_IDLEMODE;
	temp |= GPMC_SYSCONFIG_IDLEMODE_NOIDLE << GPMC_SYSCONFIG_IDLEMODE_SHIFT;
	iowrite32(temp, gpmc_reg_pointer + GPMC_SYSCONFIG/4);
	iowrite32(0x00, gpmc_reg_pointer + GPMC_IRQENABLE/4) ;
	iowrite32(0x00, gpmc_reg_pointer + GPMC_TIMEOUT_CONTROL/4);

	iowrite32((0x0 |
	(GPMC_CONFIG1_0_DEVICESIZE_SIXTEENBITS <<
		GPMC_CONFIG1_0_DEVICESIZE_SHIFT ) |
	(GPMC_CONFIG1_0_ATTACHEDDEVICEPAGELENGTH_FOUR <<
		GPMC_CONFIG1_0_ATTACHEDDEVICEPAGELENGTH_SHIFT ) |
	(GPMC_CONFIG1_0_MUXADDDATA_MUX << GPMC_CONFIG1_0_MUXADDDATA_SHIFT )), 
	gpmc_reg_pointer + GPMC_CONFIG1(csNum)/4) ;	//Address/Data multiplexed


	iowrite32((0x0 |
    	(CS_ON) |	// CS_ON_TIME
        (CS_OFF << GPMC_CONFIG2_0_CSRDOFFTIME_SHIFT) |	// CS_DEASSERT_RD
        (CS_OFF << GPMC_CONFIG2_0_CSWROFFTIME_SHIFT)),	//CS_DEASSERT_WR
	gpmc_reg_pointer + GPMC_CONFIG2(csNum)/4)  ;	

	iowrite32((0x0 |
        (ADV_ON << GPMC_CONFIG3_0_ADVONTIME_SHIFT) | //ADV_ASSERT
	(ADV_OFF << GPMC_CONFIG3_0_ADVRDOFFTIME_SHIFT) | //ADV_DEASSERT_RD
	(ADV_OFF << GPMC_CONFIG3_0_ADVWROFFTIME_SHIFT)), //ADV_DEASSERT_WR
	gpmc_reg_pointer + GPMC_CONFIG3(csNum)/4) ; 

	iowrite32( (0x0 |
	    (OE_ON << GPMC_CONFIG4_0_OEONTIME_SHIFT) |	//OE_ASSERT
	    (OE_OFF << GPMC_CONFIG4_0_OEOFFTIME_SHIFT) |	//OE_DEASSERT
	    (WR_ON << GPMC_CONFIG4_0_WEONTIME_SHIFT)| //WE_ASSERT
	    (WR_OFF << GPMC_CONFIG4_0_WEOFFTIME_SHIFT)), //WE_DEASSERT
	gpmc_reg_pointer + GPMC_CONFIG4(csNum)/4)  ; 

	iowrite32((0x0 |
	    (RD_CYC << GPMC_CONFIG5_0_RDCYCLETIME_SHIFT)|	//CFG_5_RD_CYCLE_TIM
	    (WR_CYC << GPMC_CONFIG5_0_WRCYCLETIME_SHIFT)|	//CFG_5_WR_CYCLE_TIM
	    (RD_ACC_TIME << GPMC_CONFIG5_0_RDACCESSTIME_SHIFT)),	// CFG_5_RD_ACCESS_TIM
	gpmc_reg_pointer + GPMC_CONFIG5(csNum)/4)  ;  

	iowrite32( (0x0 |
		(0 << GPMC_CONFIG6_0_CYCLE2CYCLESAMECSEN_SHIFT) |
		(0 << GPMC_CONFIG6_0_CYCLE2CYCLEDELAY_SHIFT) | //CYC2CYC_DELAY
	    (WRDATAONADMUX << GPMC_CONFIG6_0_WRDATAONADMUXBUS_SHIFT)| //WR_DATA_ON_ADMUX
	    (0 << GPMC_CONFIG6_0_WRACCESSTIME_SHIFT)), //CFG_6_WR_ACCESS_TIM
	gpmc_reg_pointer + GPMC_CONFIG6(csNum)/4) ;  

	iowrite32(( 0x09 << GPMC_CONFIG7_0_BASEADDRESS_SHIFT) | //CFG_7_BASE_ADDR
        (0x1 << GPMC_CONFIG7_0_CSVALID_SHIFT) |
        (0x0f << GPMC_CONFIG7_0_MASKADDRESS_SHIFT), //CFG_7_MASK
	gpmc_reg_pointer + GPMC_CONFIG7(csNum)/4);  
	iounmap(gpmc_reg_pointer);
	release_mem_region(SOC_GPMC_0_REGS, 720);
	return 1;
}


int LOGIBONE_fifo_open(struct inode *inode, struct file *filp)
{
    read_mode = fifo ;
    request_mem_region(FPGA_BASE_ADDR, FIFO_BLOCK_SIZE, gDrvrName); //TODO: may block EDMA transfer ...
    gpmc_cs1_virt = ioremap_nocache(FPGA_BASE_ADDR + FIFO_CMD_OFFSET, 16); //TODO: may block EDMA transfer ...
    gpmc_cs1_pointer = (unsigned short *) FPGA_BASE_ADDR ;
    fifo_size = gpmc_cs1_virt[FIFO_SIZE_OFFSET] ;
    printk("%s: Open: module opened\n",gDrvrName);
    printk("fifo size : %d\n",fifo_size);
    return 0;
}

int LOGIBONE_fifo_release(struct inode *inode, struct file *filp)
{
    printk("%s: Release: module released\n",gDrvrName);
    iounmap(gpmc_cs1_virt);
    release_mem_region(FPGA_BASE_ADDR, FIFO_BLOCK_SIZE );
    return 0;
}


unsigned short int getNbAvailable(void){
	return (gpmc_cs1_virt[FIFO_NB_AVAILABLE_B_OFFSET]*2) ;  
}

unsigned short int getNbFree(void){
	fifo_size = gpmc_cs1_virt[FIFO_SIZE_OFFSET] ;
	return ((fifo_size - gpmc_cs1_virt[FIFO_NB_AVAILABLE_A_OFFSET])*2) ;
}

ssize_t LOGIBONE_fifo_write(struct file *filp, const char *buf, size_t count,
                       loff_t *f_pos)
{
	unsigned short int transfer_size  ;
	ssize_t transferred = 0 ;
	unsigned long src_addr, trgt_addr ;
	unsigned int ret = 0;
	if(count%2 != 0){
		 printk("%s: LOGIBONE_fifo write: Transfer must be 16bits aligned.\n",gDrvrName);
		 return -1;
	}
	if(count < FIFO_BLOCK_SIZE){
		transfer_size = count ;
	}else{
		transfer_size = FIFO_BLOCK_SIZE ;
	}
	writeBuffer =  (unsigned char *) dma_alloc_coherent (NULL, count, &dmaphysbuf, 0);
	trgt_addr = (unsigned long) gpmc_cs1_pointer ;
	src_addr = (unsigned long) dmaphysbuf ;
	// Now it is safe to copy the data from user space.
	if (writeBuffer == NULL || copy_from_user(writeBuffer, buf, count) )  {
		ret = -1;
		printk("%s: LOGIBONE_fifo write: Failed copy from user.\n",gDrvrName);
		goto exit;
	}
	if(read_mode == fifo){
		while(transferred < count){
			while(getNbFree() < transfer_size) schedule() ; 
			if(edma_memtomemcpy(transfer_size, src_addr , trgt_addr, 0, INCR) < 0){
				printk("%s: LOGIBONE_fifo write: Failed to trigger EDMA transfer.\n",gDrvrName);		
				ret = -1 ;			
				goto exit;		
			}
			src_addr += transfer_size ;
			transferred += transfer_size ;
			if((count - transferred) < FIFO_BLOCK_SIZE){
				transfer_size = count - transferred ;
			}else{
				transfer_size = FIFO_BLOCK_SIZE ;
			}
		}
		ret = transferred;
	}else{
		if(edma_memtomemcpy(count, src_addr, trgt_addr, 0, INCR) < 0){
			printk("%s: LOGIBONE_fifo write: Failed to trigger EDMA transfer.\n",gDrvrName);
			ret = -1 ;
			goto exit;		
		}
		ret = count ;
	}
	exit:
	dma_free_coherent(NULL, count, writeBuffer,
				dmaphysbuf); // free coherent before copy to user
	return (ret);
}


ssize_t LOGIBONE_fifo_read(struct file *filp, char *buf, size_t count, loff_t *f_pos)
{
	unsigned short int transfer_size ;
	ssize_t transferred = 0 ;
	unsigned long src_addr, trgt_addr ;
	int ret = 0 ;
	if(count%2 != 0){
		 printk("%s: LOGIBONE_fifo read: Transfer must be 16bits aligned.\n",gDrvrName);
		 return -1 ;
	}
	if(count < FIFO_BLOCK_SIZE){
		transfer_size = count ;
	}else{
		transfer_size = FIFO_BLOCK_SIZE ;
	}
	readBuffer = (unsigned char *) dma_alloc_coherent (NULL, count, &dmaphysbuf, 0);
	src_addr = (unsigned long) gpmc_cs1_pointer ;
	trgt_addr = (unsigned long) dmaphysbuf ;
	
	if(read_mode == fifo){		
		while(transferred < count){
			while(getNbAvailable() < transfer_size) schedule() ; 
			if(edma_memtomemcpy(transfer_size, src_addr, trgt_addr, 0, INCR) < 0){
				printk("%s: LOGIBONE_fifo read: Failed to trigger EDMA transfer.\n",gDrvrName);
				goto exit ;
			}	
			trgt_addr += transfer_size ;
			transferred += transfer_size ;
			if((count - transferred) < FIFO_BLOCK_SIZE){
				transfer_size = (count - transferred) ;
			}else{
				transfer_size = FIFO_BLOCK_SIZE ;
			}
		}
		if (copy_to_user(buf, readBuffer, transferred) )  {
			ret = -1;
			goto exit;
		}		
		dma_free_coherent(NULL,  count, readBuffer,
				dmaphysbuf);	
		ret = transferred ;
	}else{
		if(edma_memtomemcpy(count,src_addr, trgt_addr, 0, INCR) < 0){
			printk("%s: LOGIBONE_fifo read: Failed to trigger EDMA transfer.\n",gDrvrName);
			goto exit ;
		}
		
		if (copy_to_user(buf, readBuffer, count) )  {
			ret = -1;
			goto exit;
		}
		dma_free_coherent(NULL, count, readBuffer, dmaphysbuf); 
		ret = count ;	
	}
	exit:
	return ret;
}


long LOGIBONE_fifo_ioctl(struct file *filp, unsigned int cmd, unsigned long arg){
		
	switch(cmd){
		case LOGIBONE_FIFO_RESET :
			gpmc_cs1_virt[FIFO_NB_AVAILABLE_A_OFFSET] = 0 ;
			gpmc_cs1_virt[FIFO_NB_AVAILABLE_B_OFFSET] = 0 ;
			return 0 ;
		case LOGIBONE_FIFO_PEEK :
			return  gpmc_cs1_virt[FIFO_PEEK_OFFSET] ;
		case LOGIBONE_FIFO_NB_FREE :
			return getNbFree() ;
		case LOGIBONE_FIFO_NB_AVAILABLE :
			return getNbAvailable() ;
		case LOGIBONE_FIFO_MODE :
			printk("switching to fifo mode \n");
			read_mode = fifo ;
			return 0 ;	
		case LOGIBONE_DIRECT_MODE :
			printk("switching to direct mode \n");
			read_mode = direct ;
			return 0 ;
		default: /* redundant, as cmd was checked against MAXNR */
			printk("unknown command %d \n", cmd);
			return -ENOTTY;
	}
}

struct file_operations LOGIBONE_fifo_ops = {
    .read =   LOGIBONE_fifo_read,
    .write =  LOGIBONE_fifo_write,
    .compat_ioctl =  LOGIBONE_fifo_ioctl,
    .unlocked_ioctl = LOGIBONE_fifo_ioctl,
    .open =   LOGIBONE_fifo_open,
    .release =  LOGIBONE_fifo_release,
};


static int LOGIBONE_fifo_init(void)
{
	dev_t dev = 0;
	struct cdev cdev ;
	int result ;
	int pinIrqLine, irq_req_res ;
	setupGPMCClock();
	if(setupGPMCNonMuxed() < 0 ){
		printk(KERN_WARNING "%s: can't initialize gpmc \n",gDrvrName);
		return -1;		
	}

	if (!gpio_is_valid(INTERRUPT_GPIO1)){
		printk(KERN_ALERT "The requested GPIO is not available \n");
		return -1 ;
	}
	if(gpio_request(INTERRUPT_GPIO1, "gpio_interrupt_1")){
		printk(KERN_ALERT "Unable to request gpio %d",INTERRUPT_GPIO1);
		return -1 ;
	}
	if(gpio_direction_input(INTERRUPT_GPIO1) < 0 ){
		printk(KERN_ALERT "Impossible to set input direction");
		return -1 ;
	}

	/*install interrupt handler*/
	if ( (pinIrqLine=gpio_to_irq(INTERRUPT_GPIO1)) < 0){
	printk(KERN_ALERT "Gpio %d cannot be used as interrupt",INTERRUPT_GPIO1);
	return -1 ;
	}
	if ( (irq_req_res = request_irq(pinIrqLine, gpio_interrupt_1, IRQF_TRIGGER_FALLING,"gpio_interrupt_1", NULL)) < 0){
		gpio_free(INTERRUPT_GPIO1);
		return -EBUSY;
	}
	printk("Interrupt in configured !\n");

	if (check_mem_region(FPGA_BASE_ADDR, 256 * sizeof(short)) ){
	    printk("%s: memory already in use\n", gDrvrName);
	    return -EBUSY;
	}
	

	if (gDrvrMajor) {
		dev = MKDEV(gDrvrMajor, gDrvrMinor);
		result = register_chrdev(gDrvrMajor, gDrvrName, &LOGIBONE_fifo_ops);
	} else {
		result = alloc_chrdev_region(&dev, gDrvrMinor, nbDevices, gDrvrName);
		gDrvrMajor = MAJOR(dev);
     		cdev_init(&cdev, &LOGIBONE_fifo_ops);
         	result = cdev_add (&cdev, MKDEV(gDrvrMajor, 0), 1);
         /* Fail gracefully if need be */
		 if (result)
		         printk(KERN_NOTICE "Error %d adding LOGIBONE_fifo%d", result, 0);
	}
	if (result < 0) {
		printk(KERN_WARNING "%s: can't get major %d\n",gDrvrName,gDrvrMajor);
		return -1;
	}
	printk(KERN_INFO"%s: Init: module registered with major number %d \n", gDrvrName, gDrvrMajor);

	printk("%s driver is loaded\n", gDrvrName);

	return 0;
}

static void LOGIBONE_fifo_exit(void)
{

    gpio_free(INTERRUPT_GPIO1);
    free_irq(pinIrqLine, NULL);
    unregister_chrdev(gDrvrMajor, gDrvrName);
    printk(/*KERN_ALERT*/ "%s driver is unloaded\n", gDrvrName);
}




/* DMA Channel, Mem-2-Mem Copy, ASYNC Mode, FIFO Mode */

int edma_memtomemcpy(int count, unsigned long src_addr, unsigned long trgt_addr,  int event_queue,  enum address_mode mode)
{
	int result = 0;
	unsigned int dma_ch = 0;
	struct edmacc_param param_set;

	result = edma_alloc_channel (EDMA_CHANNEL_ANY, dma_callback, NULL, event_queue);
	if (result < 0) {
		printk ("\nedma3_memtomemcpytest_dma::edma_alloc_channel failed for dma_ch, error:%d\n", result);
		return result;
	}

	dma_ch = result;
	if(count % 16 == 0){
		edma_set_src (dma_ch, src_addr, mode, W128BIT);
		edma_set_dest (dma_ch, trgt_addr, mode, W128BIT);
	}else if(count % 8 == 0){
		edma_set_src (dma_ch, src_addr, mode, W64BIT);
		edma_set_dest (dma_ch, trgt_addr, mode, W64BIT);
	}else if(count % 4 == 0){
		edma_set_src (dma_ch, src_addr, mode, W32BIT);
		edma_set_dest (dma_ch, trgt_addr, mode, W32BIT);
	}else{
		edma_set_src (dma_ch, src_addr, mode, W16BIT);
		edma_set_dest (dma_ch, trgt_addr, mode, W16BIT);
	}
	edma_set_src_index (dma_ch, 0, 0); // always copy from same location
	edma_set_dest_index (dma_ch, count, count); // increase by transfer size on each copy
	/* A Sync Transfer Mode */
	edma_set_transfer_params (dma_ch, count, 1, 1, 1, ASYNC); //one block of one fame of one array of count bytes

	/* Enable the Interrupts on Channel 1 */
	edma_read_slot (dma_ch, &param_set);
	param_set.opt |= ITCINTEN;
	param_set.opt |= TCINTEN;
	param_set.opt |= EDMA_TCC(EDMA_CHAN_SLOT(dma_ch));
	edma_write_slot (dma_ch, &param_set);

	result = edma_start(dma_ch);
	if (result != 0) {
		printk ("edma copy for logibone_fifo failed \n");
		
	}
	while (irqraised1 == 0u) schedule();
	irqraised1 = 0u;
	//irqraised1 = -1 ;

	/* Check the status of the completed transfer */
	if (irqraised1 < 0) {
		/* Some error occured, break from the FOR loop. */
		//printk ("edma copy for logibone_fifo: Event Miss Occured!!!\n");
	}else{
		//printk ("edma copy for logibone_fifo: Copy done !\n");
	}
	edma_stop(dma_ch);
	edma_free_channel(dma_ch);

	return result;
}

static void dma_callback(unsigned lch, u16 ch_status, void *data)
{	
	switch(ch_status) {
	case DMA_COMPLETE:
		irqraised1 = 1;
		/*printk ("\n From Callback 1: Channel %d status is: %u\n",
				lch, ch_status);*/
		break;
	case DMA_CC_ERROR:
		irqraised1 = -1;
		/*printk ("\nFrom Callback 1: DMA_CC_ERROR occured "
				"on Channel %d\n", lch);*/
		break;
	default:
		break;
	}
}

irqreturn_t gpio_interrupt_1(int irq, void *dev_id, struct pt_regs *regs)
{
  printk(KERN_ALERT "Interrupt_from_fpga\n");
  if(gpmc_cs1_virt[INTERRUPT_MANAGER_BASE_ADDR + INTERRUPT_MANAGER_INT1_OFFSET] & 0x02){
	 printk(KERN_ALERT "Interrupt 1 from fpga \n");
  }
  if(gpmc_cs1_virt[INTERRUPT_MANAGER_BASE_ADDR + INTERRUPT_MANAGER_INT2_OFFSET] & 0x02){
	 printk(KERN_ALERT "Interrupt 2 from fpga \n");
  }
  if(gpmc_cs1_virt[INTERRUPT_MANAGER_BASE_ADDR + INTERRUPT_MANAGER_INT3_OFFSET] & 0x02){
	 printk(KERN_ALERT "Interrupt 3 from fpga \n");
  }
  //can be used to signal fifo level ...
  // this means that we need to trigger a DMA chain to empty the fifo
  // also need to handle special case where FPGA may generate multiple edge when reading from the fifo ...
  // We may also setup other interrupts (up to three) to handle vertical sync signal and data ready interrupts
  return IRQ_HANDLED;
}

MODULE_LICENSE("Dual BSD/GPL");
MODULE_AUTHOR("Jonathan Piat <piat.jonathan@gmail.com>");

module_init(LOGIBONE_fifo_init);
module_exit(LOGIBONE_fifo_exit);
