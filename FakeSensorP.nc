/**
 *  Source file for implementation of module Middleware
 *  which provides the main logic for middleware message management
 *
 *  @author Michele Lucio
 */
 
generic module FakeSensorP() {

	provides interface Read<uint16_t>;
	
	uses interface Random;
	uses interface Timer<TMilli> as Timer0;

} implementation {

	//***************** Boot interface ********************//
	command error_t Read.read(){
		call Timer0.startOneShot( 10 );
		return SUCCESS;
	}
	
	uint8_t getKinematicStatus(){
		
		uint8_t kinematicStatus = call Random.rand16() % 100;

		switch(kinematicStatus){
			case 0 ... 29:
				return STANDING; //11
			break;
			case 30 ... 59:
				return WALKING; //12
			break;
			case 60 ... 89:
				return RUNNING; //13
			break;
			case 90 ... 99:
				return FALLING; //14
			break;
			default:
			return 0;
		}
	}

	//***************** Timer0 interface ********************//
	event void Timer0.fired() {
		signal Read.readDone( SUCCESS, getKinematicStatus() );
	}
}
