#Compiler to use
CC=gcc
#Compiler Flags
CFLAGS=-c #-Wall
#Linker Flags
LDFLAGS= -ljpeg -lrt

all: grabber logibone_demo

grabber: grab_frame.o jpeg_func.o
	$(CC) -o grabber grab_frame.o jpeg_func.o $(LDFLAGS) 

grab_frame.o: grab_frame.c
	$(CC) $(CFLAGS) grab_frame.c

logibone_demo: logibone_image_demo.o jpeg_func.o
	$(CC) -o logibone_demo logibone_image_demo.o jpeg_func.o $(LDFLAGS) 

logibone_image_demo.o: logibone_image_demo.c
	$(CC) $(CFLAGS) logibone_image_demo.c

jpeg_func.o: jpeg_func.c
	$(CC) $(CFLAGS) jpeg_func.c

clean:
	rm -rf *o grabber logibone_demo

