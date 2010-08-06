/******* Reflecting the Stars *********
Prototype Test 3 - SLAVE CODE
Version: 0.1.3
Authors: Richard Schwab, Corrie Van Sice, Icing Chang
Date: August 01, 2010
----------------------
Light Display Modes:
- Pulse Mode.
- Tx Reset Commands.
**************************************/

/***************** Early Definitions ******************/
#define FIRMWAREVERSION 11 // 1.1	, version number needs to fit in byte (0~255) to be able to store it into config

#define RTS_ID 2           // The Unique ID of this RFBee.
char versionblurb[100] = "v.3 - Reset Commands - SLAVE"; 
//#define FACTORY_SELFTEST
//#define INTERRUPT_RECEIVE
//#define DEBUG 


#include "debug.h"
#include "globals.h"
#include "Config.h"
#include "CCx.h"
#include "rfBeeSerial.h"

#ifdef FACTORY_SELFTEST
#include "TestIO.h"	// factory selftest
#endif

#define GDO0 2 // used for polling the RF received data

#define blue 5
#define white 6
#define SolarPin 7//used for what?
#define SolarValue 0
#define FADE_IN 0
#define FADE_OUT 1

//led states to be controlled to
enum LED_STATE{
	BLUE_ON = 1,
	WHITE_ON,
	BOTH_ON,
	BLUE_OFF,
	WHITE_OFF,
	BOTH_OFF,
	BLUE_FADE_IN,
	WHITE_FADE_IN,
	BLUE_FADE_OUT,
	WHITE_FADE_OUT,
	BOTH_FADE_IN,
	BOTH_FADE_OUT,
        RESET
};
//===================this is for slave RFBee==================

void setup(){
	//do extra initalization
	Config.set(CONFIG_MY_ADDR,RTS_ID);			//modify the numberf to specify an unique address for RFBee itself 
	setMyAddress();
	Config.set(CONFIG_ADDR_CHECK,2);	 //set slave RFBee with adress checking and broadcast
	setAddressCheck();
	//==========================
	
	if (Config.initialized() != OK) 
	{
		Serial.begin(9600);
		Serial.println("Initializing config"); 
#ifdef FACTORY_SELFTEST
		if ( TestIO() != OK ) 
			return;
#endif 
		Config.reset();
	}
	setUartBaudRate();
	rfBeeInit();
        Serial.println(versionblurb);
	Serial.println("ok");
}

void loop(){
	// Serial.print(".");
	byte result = 0;
	byte response = 'K';
	if ( digitalRead(GDO0) == HIGH ) {
		result = waitAndReceiveRFBeeData();
	}
	if( result != 0){
		transmitData(&response,1,Config.get(CONFIG_MY_ADDR),1);//transmit 'K' to the master repersenting 'ok'
		processRFBeeData(result);
	}
	/*
	if (Serial.available() > 0){
	 sleepCounter=1000; // reset the sleep counter
	 if (serialMode == SERIALCMDMODE)
	 readSerialCmd();
	 else
	 readSerialData();
	 }
	 
	 
	 
	 if ( digitalRead(GDO0) == HIGH ) {
	 writeSerialData();
	 sleepCounter++; // delay sleep
	 }
	 sleepCounter--;
	 
	 // check if we can go to sleep again, going into low power too early will result in lost data in the CCx fifo.
	 if ((sleepCounter == 0) && (Config.get(CONFIG_RFBEE_MODE) == LOWPOWER_MODE))
	 lowPowerOn();
	 */

}


void rfBeeInit(){
	DEBUGPRINT()

        CCx.PowerOnStartUp();
	setCCxConfig();

	serialMode=SERIALDATAMODE;
	sleepCounter=0;

	attachInterrupt(0, ISRVreceiveData, RISING);	//GD00 is located on pin 2, which results in INT 0

	pinMode(GDO0,INPUT);// used for polling the RF received data
}

// handle interrupt
void ISRVreceiveData(){
	sleepCounter=10;
}

byte waitAndReceiveRFBeeData()
{
	byte rxData[CCx_PACKT_LEN];
	byte len;
	byte srcAddress;
	byte destAddress;
	byte rssi;//useless for RTS
	byte lqi;//useless for RTS
	int result;


	result=receiveData(rxData, &len, &srcAddress, &destAddress, &rssi , &lqi);

	if (result == ERR) {
		writeSerialError();
		return 0;
	}

	if (result == NOTHING)
		return 0;

	//Serial.write(rxData,len);
	//Serial.print(rxData[0],HEX);
	return rxData[0];
}

//if want to control the specific pin, the pinNum1 or pinNum2 should be
//the corresponding pin number of Arduino, otherwise set pinNum to 0;
// control:0- fade in,1-fade out
void ledControl(int pinNum1, int control1, int pinNum2, int control2)
{
	for(int fadeValue = 0 ; fadeValue <= 255; fadeValue +=5){
		if(pinNum1 > 0 ){
			if(FADE_IN == control1 ){// fade in
				analogWrite(pinNum1,fadeValue);
			}
			else{//fade out
				analogWrite(pinNum1,255-fadeValue);
			}
		}
		if(pinNum2 > 0 ){
			if(FADE_IN == control2 ){// fade in
				analogWrite(pinNum2,fadeValue);
			}
			else{//fade out
				analogWrite(pinNum2,255-fadeValue);
			}
		}
		delay(30);
	}
}

void processRFBeeData( byte RFData)
{
	switch (RFData){
	case BLUE_ON:
		analogWrite(blue,255);//open blue led
		break;
	case WHITE_ON:
		analogWrite(white,255);//open white led
		break;
	case BOTH_ON:
		analogWrite(blue,255);//open both leds
		analogWrite(white,255);
		break;
	case BLUE_OFF:
		analogWrite(blue,0);//close blue led
		break;
	case WHITE_OFF:
		analogWrite(white,0);//close white led
		break;
	case BOTH_OFF:
		analogWrite(blue,0);//close both leds
		analogWrite(white,0);
		break;
	case BLUE_FADE_IN:
		ledControl(blue, FADE_IN, 0, FADE_IN);//blue fade in, white unchanged
		Serial.println("Blue Fade In");
		break;
	case WHITE_FADE_IN:
		ledControl(0, FADE_IN, white, FADE_IN);//white fade in, blue unchanged
		Serial.println("White Fade In");
		break;
	case BLUE_FADE_OUT:
		ledControl(blue, FADE_OUT, 0, FADE_OUT);//blue fade out, white unchanged
		Serial.println("Blue Fade Out");
		break;
	case WHITE_FADE_OUT:
		ledControl(0, FADE_OUT, white, FADE_OUT);//white fade out, blue unchanged
		Serial.println("White Fade Out");
		break;
	case BOTH_FADE_IN:
		ledControl(blue, FADE_IN, white, FADE_IN);//both fade in
		break;
	case BOTH_FADE_OUT:
		ledControl(blue, FADE_OUT, white, FADE_OUT);//both fade out
		break;
        case RESET:
                Serial.println("Resetting RFBee.");
                setup();
	default:
		break;										
	}
}




