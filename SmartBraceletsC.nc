/**
 *  Source file for implementation of module SmartBraceletsC in which
 *  two couple of nodes, manage a pairing phase, and after that the child device
 *  sends messages to the parents device with informations about status and position.
 *  In the case the parents device doesn't receive a message in a certain amount of time 
 *  or a FALLING message it's received, an ALLARM is sent by the parent device.
 *
 *  @author Michele Lucio
 */

#include "SmartBracelets.h"
#include "Timer.h"
#include "stdlib.h"

module SmartBraceletsC
{

	uses
	{
		/****** INTERFACES *****/
		interface Boot;
		// interfaces for communication
		interface Receive;
		interface AMSend;
		interface AMSend as AMSerialSend;
		interface SplitControl;
		interface SplitControl as SerialSplitControl;
		interface PacketAcknowledgements;
		
		// interface for timer
		interface Timer<TMilli> as PairingTimer;
		interface Timer<TMilli> as OperationTimer;
		interface Timer<TMilli> as MissingTimer;
		
		// other interfaces, if needed
		interface Packet;
		interface Packet as SerialPacket;
		
		// interface used to perform sensor reading (to get the value from a sensor)
		interface Read<uint16_t>;
		//Interface used to generate random numbers
		interface Random;
	}
}

implementation
{

	//Unique key, that identifies parent-child devices
	char deviceKey[20];

	//Coupled devices
	uint8_t linkedDevice;	

	//Current mode
	uint8_t currentMode;
	
	//Last registered position
	uint16_t last_pos_x;
	uint16_t last_pos_y;

	message_t packet;
	
	//Lock to indicate whether the radio is used or not
	bool locked;

	void getDeviceKey();
	
	char* getMessageType(uint8_t msgType);
	char* getKinematicStatus(uint16_t kStatus);

	void sendReq();
	void sendResp();
	
	void serialSend(uint16_t x, uint16_t y, uint16_t kinematicStatus);
	
	void getDeviceKey(){
		uint8_t i=0;
		FILE *fp;
		fp = fopen("DeviceKey.txt", "r");
		if(fp == NULL){
			dbg("boot", "File di configurazione non trovato, lo creo\n");
			dbg("boot", "Sono un parent device, creo una nuova chiave\n");
			fp = fopen("DeviceKey.txt", "w");
			for(i=0; i<20; i++)	{
				char toSave = 'A' + call Random.rand16() % 26;
				fputc(toSave, fp);
				deviceKey[i] = toSave;
			}
			//dbg_clear("radio_pack", "\t\t TEST file di config scritto, lunghezza: %hhu \n", strlen(deviceKey));
		}else{
			if(TOS_NODE_ID%2==0){
				//Child node reads the key from the file
				dbg("boot", "File di configurazione trovato, lo leggo\n");
				dbg("boot", "Sono un child device, leggo la chiave dal file\n");
				fp = fopen("DeviceKey.txt", "r");
				fseek(fp, -20, SEEK_END);
				for(i=0; i<20; i++)	{
					deviceKey[i] = fgetc(fp);
				}
				//dbg_clear("radio_pack", "\t\t TEST file di config letto, lunghezza: %hhu \n", strlen(deviceKey));
			}
			else{
				//Father node request a new key
				dbg("boot", "File di configurazione trovato\n");
				dbg("boot", "Sono un parent device, creo una nuova chiave\n");
				fp = fopen("DeviceKey.txt", "a");
				fputc('\n', fp);
				for(i=0; i<20; i++)	{
					char toSave = 'A' + call Random.rand16() % 26;
					fputc(toSave, fp);
					deviceKey[i] = toSave;
				}
			}	
		}
		fclose(fp);
	}
	
	char* getMessageType(uint8_t msgType){
		switch(msgType){
			case PAIRING:
				return "PAIRING";
			break;
			case CLOSE_PAIRING:
				return "CLOSE_PAIRING";
			break;
			case OPERATION_MODE:
				return "OPERATION_MODE";
			break;
			case INFO:
				return "INFO";
			break;
			default:
			return 0;
		}
	}

	char* getKinematicStatus(uint16_t kStatus){
		switch(kStatus){
			case STANDING:
				return "STANDING";
			break;
			case WALKING:
				return "WALKING";
			break;
			case RUNNING:
				return "RUNNING";
			break;
			case FALLING:
				return "FALLING";
			break;
			default:
			return 0;
		}
	}

	//***************** Send request function ********************//
	void sendReq()
	{
		/* This function is called when we want to send a request
		 *
		 * STEPS:
		 * 1. Prepare the msg
		 * 2. Set the ACK flag for the message using the PacketAcknowledgements interface
		 *     (read the docs)
		 * 3. Send an UNICAST message to the correct node
		 * X. Use debug statements showing what's happening (i.e. message fields)
		 */
		uint8_t i=0;
		am_addr_t dest=0;

		my_msg_t *rcm = (my_msg_t *)call Packet.getPayload(&packet, sizeof(my_msg_t));
		if (rcm == NULL)
		{
			// C'è stato qualche problema con il pacchetto quindi ritorna
			return;
		}

 		dbg("radio","---------------SENDING-----------------\n");
		// Scrivo i dati nel pacchetto da inviare
		dbg("radio_pack", "Preparing the message... \n");
		dbg("radio_pack", "Current mode: %s\n",getMessageType(currentMode));
		switch(currentMode){
		
			case PAIRING:
				rcm->msgType = PAIRING;
				dest = AM_BROADCAST_ADDR;
				dbg("radio_pack", "Destination: BROADCAST\n");
			break;
			
			case CLOSE_PAIRING:
				rcm->msgType = CLOSE_PAIRING;
				dest = linkedDevice;
				dbg("radio_pack", "Destinatario: %hhu\n",dest);
				dbg("radio_pack", "Richiedo l'ACK per il messaggio! \n");
				call PacketAcknowledgements.requestAck(&packet);
			break;
			
			case OPERATION_MODE:
				dbg("radio_pack", "TEST: sono in OPERATION MODE preparo il pacchetto...\n");
			break;
			
		}
		
		for(i = 0; i < 20 ;i++){
			rcm->key[i] = (nx_uint8_t)deviceKey[i];
		}
		rcm->sendingDeviceID = TOS_NODE_ID;

		if (call AMSend.send(dest, &packet, sizeof(my_msg_t)) == SUCCESS)
		{
			dbg("radio_send", "Sending the packet at time %s \n", sim_time_string());
			dbg("radio_pack", ">>>Pack\n \t Payload length: %hhu \n", call Packet.payloadLength(&packet));
			dbg_clear("radio_pack", "\t Payload Sent\n");
			dbg_clear("radio_pack", "\t\t msgType: %s \n ", getMessageType(rcm->msgType) );
			dbg_clear("radio_pack", "\t\t deviceKey: ");
				for(i = 0; i < 20 ;i++)	dbg_clear("radio_pack","%c",rcm->key[i]);
				dbg_clear("radio_pack", "\n");
			//dbg_clear("radio_pack", "\t\t TEST STRLEN: %hhu \n", strlen(rcm->key));
			dbg_clear("radio_pack", "\t\t sendingDeviceID: %hhu \n", rcm->sendingDeviceID);

			locked = TRUE;
		}
	}
	
	void serialSend(uint16_t x, uint16_t y, uint16_t kinematicStatus){
	
		serial_msg_t *rcm = (serial_msg_t *)call SerialPacket.getPayload(&packet, sizeof(serial_msg_t));
		if (rcm == NULL){
			// C'è stato qualche problema con il pacchetto quindi ritorna
			return;
		}
		if (call SerialPacket.maxPayloadLength() < sizeof(serial_msg_t)) {
			return;
		}
		
		//Settare campi messaggio da inviare
		rcm->pos_X = x;
		rcm->pos_Y = y;
		rcm->kinematicStatus = kinematicStatus;
		
		if (call AMSerialSend.send(AM_BROADCAST_ADDR, &packet, sizeof(serial_msg_t)) == SUCCESS){
			dbg("radio_send", "Sending the SERIAL packet at time %s \n", sim_time_string());
			dbg("radio_pack", ">>>Pack\n \t Payload length: %hhu \n", call SerialPacket.payloadLength(&packet));
			dbg_clear("radio_pack", "\t Payload Sent\n");
			dbg_clear("radio_pack", "\t\t X : %hu \n ", getMessageType(rcm->pos_X) );
			dbg_clear("radio_pack", "\t\t Y : %hu \n ", getMessageType(rcm->pos_Y) );
			dbg_clear("radio_pack", "\t\t Kinematic Status : %s \n ", getKinematicStatus(rcm->kinematicStatus) );
		}
		
	}

	//****************** Task send response *****************//
	void sendResp()
	{
		/* This function is called when we receive the REQ message.
		 * Nothing to do here.
		 * `call Read.read()` reads from the fake sensor.
		 * When the reading is done it raises the event read done.
		 */
		call Read.read();
		
	}

	//***************** Boot interface ********************//
	event void Boot.booted()
	{
		dbg_clear("boot", "\n\n");
		dbg("boot", "Application booted on node %u.\n", TOS_NODE_ID);
		dbg("boot", "Boot at time %s \n", sim_time_string());
	
		getDeviceKey();
		dbg("boot", "Device key: %s\n", deviceKey);
		
		dbg("boot", "-----Entering in PAIRING MODE:-----\n");
		currentMode = PAIRING;
		
		call SplitControl.start();
		call SerialSplitControl.start();

	}

	//***************** SplitControl interface ********************//
	event void SplitControl.startDone(error_t err)
	{
		if (err == SUCCESS)
		{
			dbg("radio", "Radio on on node %d!\n", TOS_NODE_ID);

			dbg("boot", "Sono il Nodo %u, attivo il PAIRING timer.\n", TOS_NODE_ID);
			call PairingTimer.startPeriodic(1000);

		}
		else
		{
			call SplitControl.start();
		}
	}
	
	event void SerialSplitControl.startDone(error_t err){}

	event void SplitControl.stopDone(error_t err)
	{
		/* Fill it ... */
		dbg("boot", "Radio stopped!\n");
	}
	
	event void SerialSplitControl.stopDone(error_t err){}

	//***************** Timer interfaces ********************//
	//**** (PairingTimer, OperationTimer, MissingTimer) ****//
	event void PairingTimer.fired()
	{

		/* This event is triggered every time the timer fires.
		 * When the timer fires, we send a request
		 * Fill this part...
		 */
		dbg_clear("radio_ack", "\n");
		dbg("radio_ack", "Pairing Timer fired. \n");
		// la radio è occupata, quindi skippa l'evento e la utlizzerà al prossimo evento timer
		if (locked)
		{
			return;
		}
		else
		{
			sendReq();
		}
	}
	
	event void OperationTimer.fired(){
		dbg_clear("radio_ack", "\n");
		dbg("radio_ack", "Operation Timer fired at time %s \n", sim_time_string());	
		if (locked)
		{
			return;
		}
		else
		{
			sendResp();
		}
	}
	
	event void MissingTimer.fired(){
		dbg_clear("radio_ack", "\n");
		dbg("radio_ack", "Missing Timer fired at time %s \n", sim_time_string());	
		if (locked)
		{
			return;
		}
		else
		{
			dbg("radio_rec", "****************************************************************\n");
			dbg("radio_rec", "** MISSING TIMER:  %s                           **\n", sim_time_string());
			dbg("radio_rec", "** no message received from the coupled device in 1 minute:   **\n");
			dbg("radio_rec", "****************************************************************\n");
			dbg("radio_rec", "** LAST RECEIVED POSITION *******\n");
			dbg("radio_rec", "** X: %10hu               **\n", last_pos_x);
			dbg("radio_rec", "** Y: %10hu               **\n", last_pos_y);
			dbg("radio_rec", "*********************************\n");
			
			serialSend(last_pos_x, last_pos_y, MISSING);
		}
	}

	//********************* AMSend interface ****************//
	event void AMSend.sendDone(message_t * buf, error_t err)
	{
		/* This event is triggered when a message is sent
		 *
		 * STEPS:
		 * 1. Check if the packet is sent
		 * 2. Check if the ACK is received (read the docs)
		 * X. Use debug statements showing what's happening (i.e. message fields)
		 */

		if (&packet == buf && err == SUCCESS)
		{
			locked = FALSE;
			dbg("radio_send", "Packet correctly sent...");
			dbg_clear("radio_send", " at time %s \n", sim_time_string());
			
			
			if(currentMode == CLOSE_PAIRING){
				if (call PacketAcknowledgements.wasAcked(&packet)){
					dbg("radio_send", "Ack ricevuto\n");
					dbg("radio_rec", "Termino timer per pairing:\n");
					call PairingTimer.stop();
					dbg("radio_rec", "-----Entering in OPERATION MODE:-----\n");
					currentMode = OPERATION_MODE;
					call OperationTimer.startPeriodic(1000*10);
				}else{
					dbg("radio_send", "*********Ack NON ricevuto***********\n");
				}
			}
			else if(currentMode == OPERATION_MODE){
				if (call PacketAcknowledgements.wasAcked(&packet)){
					dbg("radio_send", "Ack per INFO msg ricevuto\n");
				}else{
					dbg("radio_send", "*********Ack per INFO msg NON ricevuto***********\n");
				}
			}
			
		}
		else
		{
			dbgerror("radio_send", "Send done error!\n");
		}
	}
	
	event void AMSerialSend.sendDone(message_t* buf,error_t err) {}

	//***************************** Receive interface *****************//
	event message_t *Receive.receive(message_t * buf, void *payload, uint8_t len)
	{
		uint8_t i=0;
		/* This event is triggered when a message is received
		 *
		 * STEPS:
		 * 1. Read the content of the message
		 * 2. Check if the type is request (REQ)
		 * 3. If a request is received, send the response
		 * X. Use debug statements showing what's happening (i.e. message fields)
		 */
		 
		my_msg_t* mess = (my_msg_t*)payload;
		 
		 // In operation mode, the node accepts only messages 
		 // coming from the child's bracelet
		 if( currentMode == OPERATION_MODE && linkedDevice != mess->sendingDeviceID ){
		 	dbg("radio_rec", "Received packet from unPaired Device \n");
		 	return buf;
		 }
		 
 		 dbg("radio","---------------RECEIVING-----------------\n");

		 if (len != sizeof(my_msg_t)) {
		 	return buf;
		 }
		 else {
      		
      		//dbg("radio_rec", "Sono mote#2 ho ricevuto il pacchetto\n");
      			
      		dbg("radio_rec", "Received packet at time %s\n", sim_time_string());
  			dbg("radio_pack", ">>>Pack\n \t Payload length: %hhu \n", call Packet.payloadLength(&packet));
			dbg_clear("radio_pack", "\t Payload Sent\n");
      		dbg_clear("radio_pack", "\t\t msgType: %s \n ", getMessageType(mess->msgType));
			dbg_clear("radio_pack", "\t\t deviceKey: ");
				for(i = 0; i < 20 ;i++)	dbg_clear("radio_pack","%c",mess->key[i]);
				dbg_clear("radio_pack", "\n");
			//dbg_clear("radio_pack", "\t\t TEST STRLEN: %hhu \n", strlen(mess->key));
			dbg_clear("radio_pack", "\t\t sendingDeviceID: %hhu \n", mess->sendingDeviceID);
			
			if(mess->msgType == INFO){
				dbg_clear("radio_pack", "\t\t Pos_X: %hu \n", mess->pos_X);
				dbg_clear("radio_pack", "\t\t Pos_Y: %hu \n", mess->pos_Y);
				dbg_clear("radio_pack", "\t\t Kinematic status: %s \n", getKinematicStatus(mess->kinematicStatus) );
			}


			//RESPONSE mote2
			if(mess->msgType == CLOSE_PAIRING){
				dbg("radio_rec", "-----Entering in CLOSE_PAIRING MODE:-----\n");
				currentMode = CLOSE_PAIRING;
				linkedDevice = (uint8_t)mess->sendingDeviceID;
			}
			
			//REQUEST mote1
			if(currentMode == PAIRING){
				//Check if the devices keys are equals
				for(i = 0; i < 20 ;i++){
					if(deviceKey[i] != mess->key[i]){
						dbg("radio_rec", "Dispositivo non associabile!\n");					
				    	return buf;
					}
				}
				dbg("radio_rec", "Trovato dispositivo per associazione!\n");
				linkedDevice = (uint8_t)mess->sendingDeviceID;
				dbg("radio_rec", "-----Entering in CLOSE_PAIRING MODE:-----\n");
				currentMode = CLOSE_PAIRING;
				sendReq();
			}
			//mote1
			else if(currentMode == CLOSE_PAIRING){
				dbg("radio_rec", "Associato con il dispositivo %hhu, termino il pairing!\n", linkedDevice);
				dbg("radio_rec", "Termino timer per pairing:\n");
				call PairingTimer.stop();
				dbg("radio_rec", "-----Entering in OPERATION MODE:-----\n");
				currentMode = OPERATION_MODE;
			}
			
			if(mess->msgType == INFO && mess->sendingDeviceID == linkedDevice){
				dbg("radio_rec", "Ricevuto messaggio dal dispositivo accoppiato:\n");
				dbg("radio_rec", "Stop Missing Timer:\n");
				call MissingTimer.stop();
				call MissingTimer.startOneShot(1000*60);
				//Salvo le posizioni x,y
				last_pos_x = mess->pos_X;
				last_pos_y = mess->pos_Y;
				
				if(mess->kinematicStatus == FALLING){
					//Sends a FALL alarm reporting the position x,y
					dbg("radio_rec", "*****************************\n");
					dbg("radio_rec", "** FALLING status received **\n");
					dbg("radio_rec", "** from the coupled device **\n");
					dbg("radio_rec", "*****************************\n");
					dbg("radio_rec", "** FALLING POSITIONS       **\n");
					dbg("radio_rec", "** X: %10hu           **\n", mess->pos_X);
					dbg("radio_rec", "** Y: %10hu           **\n", mess->pos_Y);
					dbg("radio_rec", "*****************************\n");
					
					serialSend(mess->pos_X, mess->pos_Y, FALLING);
				}
			}


			//sendResp();
      		
	    	
	    	return buf;
		}
    	
      	dbgerror("radio_rec", "Receiving error \n");
    	
	}

	//************************* Read interface **********************//
	event void Read.readDone(error_t result, uint16_t data)
	{
		/* This event is triggered when the fake sensor finishes to read (after a Read.read())
		 *
		 * STEPS:
		 * 1. Prepare the response (RESP)
		 * 2. Send back (with a unicast message) the response
		 * X. Use debug statement showing what's happening (i.e. message fields)
		 */
		 
		my_msg_t *rcm = (my_msg_t *)call Packet.getPayload(&packet, sizeof(my_msg_t));
		if (rcm == NULL)
		{
			// C'è stato qualche problema con il pacchetto quindi ritorna
			return;
		}

		dbg("radio_pack", "Kinematic Status letto dal sensore: %s \n",getKinematicStatus(data) );

		// Scrivo i dati nel pacchetto da inviare
		dbg("radio_pack", "Preparing the response-message... \n");

		rcm->msgType = INFO;
//		rcm->key[20];
//		rcm->sendingDeviceID = TOS_NODE_ID;
		rcm->pos_X = call Random.rand16();
		rcm->pos_Y = call Random.rand16();
		rcm->kinematicStatus = data;

		dbg("radio_send", "Richiedo l'ACK per il messaggio! \n");
		call PacketAcknowledgements.requestAck(&packet);

		if (call AMSend.send(linkedDevice, &packet, sizeof(my_msg_t)) == SUCCESS)
		{
			dbg("radio_send", "Sending the packet at time %s \n", sim_time_string());
			dbg("radio_pack", ">>>Pack\n \t Payload length: %hhu \n", call Packet.payloadLength(&packet));
			dbg_clear("radio_pack", "\t Payload Sent\n");
			dbg_clear("radio_pack", "\t\t msgType: %s \n ", getMessageType(rcm->msgType));
			dbg_clear("radio_pack", "\t\t Pos_X: %hu \n", rcm->pos_X);
			dbg_clear("radio_pack", "\t\t Pos_Y: %hu \n", rcm->pos_Y);
			dbg_clear("radio_pack", "\t\t Kinematic Status: %s \n", getKinematicStatus(rcm->kinematicStatus) );

			locked = TRUE;
		}
	}
}
