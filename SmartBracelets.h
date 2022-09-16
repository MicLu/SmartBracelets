/**
 *  Header file for SmartBracelets project
 *
 *  @author Michele Lucio
 */

#ifndef SMARTBRACELETS_H
#define SMARTBRACELETS_H

//payload of the msg
typedef nx_struct my_msg {
	nx_uint8_t msgType;
	nx_uint8_t key[20];
	nx_uint8_t sendingDeviceID;
	nx_uint16_t pos_X;
	nx_uint16_t pos_Y;
	nx_uint16_t kinematicStatus;	
} my_msg_t;

typedef nx_struct serial_msg {
	nx_uint16_t pos_X;
	nx_uint16_t pos_Y;
	nx_uint16_t kinematicStatus;	
} serial_msg_t;

/*
typedef nx_struct my_sensor_msg {
	nx_uint8_t msgType;
	nx_uint8_t sendingDeviceID;
	nx_uint8_t pos_X;
	nx_uint8_t pos_Y;
	nx_uint8_t kinematicStatus;
} info_msg;*/

//MESSAGE TYPE
#define PAIRING 		1
#define CLOSE_PAIRING 	2
#define OPERATION_MODE 	3
#define INFO 			4

//KINEMATIC STATUS
#define STANDING 	11
#define WALKING 	12
#define RUNNING		13
#define FALLING 	14

#define MISSING 	15

//#define RESP 21

enum{
AM_MY_MSG = 6, AM_SERIAL_MSG = 0x89,
};

#endif
