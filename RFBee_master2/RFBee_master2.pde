/******* Reflecting the Stars *********
Prototype Test 2 - MASTER CODE
Version: 0.1.2
Authors: Richard Schwab, Corrie Van Sice, Icing Chang
Date: August 04, 2010
----------------------
Light Display Modes:
- Pulse Mode.
**************************************/


#define FIRMWAREVERSION 11 // 1.1  , version number needs to fit in byte (0~255) to be able to store it into config
//#define FACTORY_SELFTEST
//#define INTERRUPT_RECEIVE
//#define DEBUG 


#include "debug.h"
#include "globals.h"
#include "Config.h"
#include "CCx.h"
#include "rfBeeSerial.h"

#ifdef FACTORY_SELFTEST
#include "TestIO.h"  // factory selftest
#endif

#define GDO0 2 // used for polling the RF received data

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

byte len = 1;              // Length of data to be sent

//================this is for Master RFBee======================

void setup(){
  //do extra initalization
  Config.set(CONFIG_MY_ADDR,0);//specify an unique address 1 for Master RFBee 
  setMyAddress();
  Config.set(CONFIG_ADDR_CHECK,1);
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
    Serial.println("ok");
}

void loop(){
  //comment this when as a Master
 
  static byte destAddr = 1;     // Initial with address 1
  byte maxSlaveAddr = 30;       // The Maximum amount of Slaves in this Network
  unsigned long startTime;  
  byte response = 0;
  static byte allOver = 0;
  
  switch(allOver) {
    case 0: 
      serialData[0] = WHITE_FADE_IN;    //choose from LED_STATE
      Serial.print(destAddr, DEC);
      Serial.println(" White..");
      break;
      
    case 1:
      serialData[0] = WHITE_FADE_OUT;
      //transmitData(&serialData[0],len,Config.get(CONFIG_MY_ADDR),destAddr);//Config.get(CONFIG_DEST_ADDR));//transmit 
      break;
   
    case 2:
      serialData[0] = BLUE_FADE_IN;
      Serial.print(destAddr, DEC);
      Serial.println(" Blue..");
      //transmitData(&serialData[0],len,Config.get(CONFIG_MY_ADDR),destAddr);//Config.get(CONFIG_DEST_ADDR));//transmit 
      break;
  
    case 3:
      //delay(250);
      serialData[0] = BLUE_FADE_OUT;
      //serialData[0] = WHITE_FADE_OUT;
      break;
    case 4:
      serialData[0] = RESET;
      break;
  }
  
  transmitData(&serialData[0],len,Config.get(CONFIG_MY_ADDR),destAddr);  //Config.get(CONFIG_DEST_ADDR));//transmit
  
  //serialData[0] = BOTH_OFF;
  //transmitData(&serialData[0],len,Config.get(CONFIG_MY_ADDR),destAddr);  //Config.get(CONFIG_DEST_ADDR));//transmit 
 
 /* 
  if(0 == allOver) {
    
    serialData[0] = BLUE_FADE_IN;
     Serial.println("Fading Out Blue..");
  }
  else {
     serialData[0] = BLUE_FADE_OUT;
     Serial.println("Fading Out Blue..");
     delay(1000);  //have some delay
     serialData[0] = WHITE_FADE_IN;
     Serial.println("Fading Out Blue..");
  } */
  //Config.set(CONFIG_DEST_ADDR,destAddr);//it's unnecessary   
  
 /* 
  startTime= millis();
  while((millis() >= startTime)&&(millis() - startTime < 20))
  {
    if ( digitalRead(GDO0) == HIGH ){
      if(1 == waitAndProcessRFBeeData()){
        response = 1;
        break;
      }
    }
  }*/
  //if( 0 == response )
    //return;
    
  destAddr++;//increase the destination address
  //delay(1000);
  if(destAddr>maxSlaveAddr){// when reach the max address, return to 2
    destAddr = 1;
    //allOver = 1 - allOver;    // if you only have two cases for allOver (0 and 1)
    if(allOver==4)
      allOver=0;
    else
      allOver++;
    
    delay(2000);
  }
  
  //Serial.println("Sending to: ");
  //Serial.println(destAddr, DEC);
  //Serial.println(destAddr, BYTE);
  
  //delay(500);//have some delay
  /*
  if (Serial.available() > 0){
    sleepCounter=1000; // reset the sleep counter
    if (serialMode == SERIALCMDMODE)
      readSerialCmd();
    else
      readSerialData();
  }


//#ifdef USE_INTERRUPT_RECEIVE   
//  if (state==RECV_WAITING)
//     writeSerialData();
//#else // polling mode
  if ( digitalRead(GDO0) == HIGH ) {
      writeSerialData();
      sleepCounter++; // delay sleep
  }
  sleepCounter--;
  
  // check if we can go to sleep again, going into low power too early will result in lost data in the CCx fifo.
  if ((sleepCounter == 0) && (Config.get(CONFIG_RFBEE_MODE) == LOWPOWER_MODE))
    lowPowerOn();
      */
//#endif
}


void rfBeeInit(){
    DEBUGPRINT()
    
    CCx.PowerOnStartUp();
    setCCxConfig();
   
    serialMode=SERIALDATAMODE;
    sleepCounter=0;
    
    attachInterrupt(0, ISRVreceiveData, RISING);  //GD00 is located on pin 2, which results in INT 0
    pinMode(GDO0,INPUT);// used for polling the RF received data

    //serialData[0] = BOTH_FADE_OUT;
    //transmitData(&serialData[0],len,Config.get(CONFIG_MY_ADDR),3);//Config.get(CONFIG_DEST_ADDR));//transmit 
  

}

// handle interrupt
void ISRVreceiveData(){
  sleepCounter=10;
}

byte waitAndProcessRFBeeData()
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

  Serial.write(rxData,len);
  Serial.println("");
  if('K' == rxData[0])
    return 1;
  else
    return 0;
}


