/******* Reflecting the Stars *********
Prototype Test 4 - SLAVE CODE
Version: 0.1.4
Authors: Richard Schwab, Corrie Van Sice, Icing Chang, Adam Berenzweig
Date: August 05, 2010
----------------------
Light Display Modes:
- Pulse Mode.
- Tx Reset Commands.
- Sleep.
**************************************/

/***************** Early Definitions ******************/
#define FIRMWAREVERSION 11 // 1.1	, version number needs to fit in byte (0~255) to be able to store it into config

#define RTS_ID 2           // The Unique ID of this RFBee.
char versionblurb[100] = "v.4 - Rx Sleep when Lonely - SLAVE"; 
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

//#define blue_pin 5
//#define white_pin 6
#define SolarPin 7//used for what?
#define SolarValue 0

#define rx_lonely_sleep 30000 // Amount of loops to go through without Tx before the Rx goes to sleep.
int rx_lonely_counter=0;
int misc_counter=0;

// FIXME macros or global ints?
#define FADE_INTERVAL_MS 30
#define FADE_INCREMENT 5
#define MAX_FADE_VALUE 255
#define MIN_FADE_VALUE 0

enum LEDS {
  blue,
  white,
  NUM_LEDS
};

// FIXME classes in arduino? want to encapsulate this.
int led_state[NUM_LEDS];
int fade_value[NUM_LEDS];
int pin_number[NUM_LEDS];

unsigned long last_led_control_time;

//led states to be controlled to
enum RTS_COMMAND {
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
        RESET,
        REBOOT
};

// What a LED is doing right now.
enum LED_STATE {
  LED_OFF,
  LED_ON,
  FADE_IN,
  FADE_OUT
};

//===================this is for slave RFBee==================

void setup(){
	//do extra initalization
	Config.set(CONFIG_MY_ADDR,RTS_ID);        //modify the numberf to specify an unique address for RFBee itself 
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
        InitLedStates();
        Serial.println(versionblurb);
        Serial.print("RTS Unique ID: ");
        Serial.println(RTS_ID, DEC);
	Serial.println("ok");
}

void InitLedStates() {
   pin_number[blue] = 5;
   pin_number[white] = 6;
   for (int i = 0; i < NUM_LEDS; ++i) {
     fade_value[i] = MIN_FADE_VALUE;
     led_state[i] = LED_OFF;
   }
  last_led_control_time = millis();
}

void loop(){
	// Serial.print(".");
	byte result = 0;
	byte response = 'K';
        
        misc_counter++;
        
        // Listen for Tx Signals.
	if ( digitalRead(GDO0) == HIGH ) {
                Serial.print("Rx ==> ");
                rx_lonely_counter=0;
		result = waitAndReceiveRFBeeData();
	}
        else {    // If no Tx, we're either under water or just not active so go to sleep.
          if (misc_counter % 12 == 0) {
            misc_counter=0;
            rx_lonely_counter++;
            if(rx_lonely_counter%10000 == 0) {
              Serial.print("Lonely Counter: ");
              Serial.println(rx_lonely_counter/10000, DEC);
            }
          }
        }
	if( result != 0){
		//transmitData(&response,1,Config.get(CONFIG_MY_ADDR),1);//transmit 'K' to the master repersenting 'ok'
		processRFBeeData(result);
	}

        MaybeRunLedControl();


        // Lonely Timer - for when the Rx no longer hears from the Tx, it will go to sleep.
        /*
        if((rx_lonely_counter == rx_lonely_sleep)) {
          Serial.println("");
          Serial.println("Going to Sleep...");
          TurnOffLightsNice();
          lowPowerOn();    // Only drops to 20ma from 24ma operating
        }
        */
        
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


void MaybeRunLedControl() {
  unsigned long now = millis();
  if (now < last_led_control_time) {
    // time overflow, happens every 50 days
    last_led_control_time = 0;
  }
  if (now < FADE_INTERVAL_MS) {
    // Don't underflow the subtraction.
    return;
  }
  if (last_led_control_time < now - FADE_INTERVAL_MS) {
    last_led_control_time = now;
    LedControlTimeSlice();
  }
}

// Each led has a state:  { LED_OFF, LED_ON, FADE_IN, FADE_OUT }
// and a value (fade_value[led]).
// ledControlTimeSlice is called every N milliseconds.  It looks at each state and either:
//   LED_OFF, LED_ON: do nothing
//   FADE_IN, OUT: increment or decrement fadeValue and analogWrite, until hit limit (0, 255), then switch state to OFF/ON.
void LedControlTimeSlice() {
  for (int led = 0; led < NUM_LEDS; ++led) {
    switch (led_state[led]) {
      case LED_OFF:
        break;
      case LED_ON:
        break;
      case FADE_IN:
        fade_value[led] += FADE_INCREMENT;
        if (fade_value[led] >= MAX_FADE_VALUE) {
          fade_value[led] = MAX_FADE_VALUE;
          led_state[led] = LED_ON;
        }
        analogWrite(pin_number[led], fade_value[led]);
        break;
      case FADE_OUT:
        fade_value[led] -= FADE_INCREMENT;
        if (fade_value[led] <= MIN_FADE_VALUE) {
          fade_value[led] = MIN_FADE_VALUE;
          led_state[led] = LED_OFF;
        }
        analogWrite(pin_number[led], fade_value[led]);
        break;
    }
  }
}

void SetLedState(int led, int state) {
  led_state[led] = state;
  Serial.print("Set led ");
  Serial.print(led, DEC);
  Serial.print(" to state ");
  Serial.println(state, DEC);
}

void TurnOffLightsNice() {
 if(analogRead(white) > 120)
   SetLedState(white, FADE_OUT);
 if(analogRead(blue) > 120)
   SetLedState(blue, FADE_OUT);
}

void processRFBeeData( byte RFData)
{
  // FIXME: MAX_FADE_VALUE, etc
  // FIXME: Don't really need to analogWrite here, will pick up the state change in the next LedControlTimeSlice.
	switch (RFData){
	case BLUE_ON:
		analogWrite(pin_number[blue],255);
                SetLedState(blue, LED_ON);
		break;
	case WHITE_ON:
                SetLedState(white, LED_ON);
		analogWrite(pin_number[white],255);
		break;
	case BOTH_ON:
                SetLedState(blue, LED_ON);
                SetLedState(white, LED_ON);
		analogWrite(pin_number[blue],255);
		analogWrite(pin_number[white],255);
		break;
	case BLUE_OFF:
                SetLedState(blue, LED_OFF);
		analogWrite(pin_number[blue],0);
		break;
	case WHITE_OFF:
                SetLedState(white, LED_OFF);
		analogWrite(pin_number[white],0);
		break;
	case BOTH_OFF:
                SetLedState(blue, LED_OFF);
                SetLedState(white, LED_OFF);
		analogWrite(pin_number[blue],0);
		analogWrite(pin_number[white],0);
		break;
	case BLUE_FADE_IN:
                SetLedState(blue, FADE_IN);
		Serial.println("Blue Fade In");
		break;
	case WHITE_FADE_IN:
                SetLedState(white, FADE_IN);
		Serial.println("White Fade In");
		break;
	case BLUE_FADE_OUT:
                SetLedState(blue, FADE_OUT);
		Serial.println("Blue Fade Out");
		break;
	case WHITE_FADE_OUT:
                SetLedState(white, FADE_OUT);
		Serial.println("White Fade Out");
		break;
	case BOTH_FADE_IN:
                SetLedState(white, FADE_IN);
                SetLedState(blue, FADE_IN);
                break;
	case BOTH_FADE_OUT:
                SetLedState(white, FADE_OUT);
                SetLedState(blue, FADE_OUT);
		break;
        case RESET:
                Serial.println("Resetting RFBee.");
                Serial.println("");
                setup();
                break;
        case REBOOT:
                Serial.println("Rebooting RFBee (EEProm).");
                Serial.println("");
                Config.reset();
                break;
	default:
		break;										
	}
}




