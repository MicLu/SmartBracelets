/**
 *  Configuration file for wiring of SmartBraceletsC module to other common 
 *  components needed for proper functioning
 * 
 *  @author Michele Lucio
 */

#include "SmartBracelets.h"

configuration SmartBraceletsAppC {}

implementation {


/****** COMPONENTS *****/
  components MainC, RandomC, SmartBraceletsC as App;
  //add the other components here
  components new AMSenderC(AM_MY_MSG);
  components new AMReceiverC(AM_MY_MSG);

  components new TimerMilliC() as PairingTimer;
  components new TimerMilliC() as OperationTimer;
  components new TimerMilliC() as MissingTimer;

  components ActiveMessageC;
  components SerialActiveMessageC;
  components new FakeSensorC();

/****** INTERFACES *****/
  //Boot interface
  App.Boot -> MainC.Boot;

  /****** Wire the other interfaces down here *****/
  
  //Send and Receive interfaces
  App.Receive -> AMReceiverC;
  App.AMSend -> AMSenderC;
  App.AMSerialSend -> SerialActiveMessageC.AMSend[AM_SERIAL_MSG];
  
  //Radio Control    
  App.SplitControl -> ActiveMessageC;
  App.SerialSplitControl -> SerialActiveMessageC;


  
  //Interfaces to access package fields
  App.Packet -> AMSenderC;
  App.SerialPacket -> SerialActiveMessageC;
  
  //Timer interface
  App.PairingTimer -> PairingTimer;
  App.OperationTimer -> OperationTimer;
  App.MissingTimer -> MissingTimer;
  
  //Fake Sensor read
  App.Read -> FakeSensorC;
  
  //Random number generator
  App.Random -> RandomC;
  RandomC <- MainC.SoftwareInit;
  
  App.PacketAcknowledgements -> ActiveMessageC;

}

