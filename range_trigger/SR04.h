#ifndef SR04_H
#define SR04_H

#if defined(ARDUINO) && ARDUINO >= 100
	#include "Arduino.h"
#else
	#include "WProgram.h"
#endif
//#include "pins_arduino.h"

#include <inttypes.h>

#define PULSE_TIMEOUT 150000L	// 100ms
#define DEFAULT_DELAY 10
#define DEFAULT_PINGS 5
class SR04 {
public:
	
	/**
	* Constructor
	* Ultrasonic sensor SR04, four connections pins
	* VCC, ECHO, TRIGGER, GND
	* <br>
	* \param echoPin digital INPUT-Pin for measuring distance
	* \param triggerPin if 10us high a trigger signal is generated from 
	*					SR04
	*
	* \return void
	*/
	SR04(int echoPin, int triggerPin);

	/**
	* Do a measurment for this sensor. Return distance as long
	* in centimenter
	* \return long distance in centimeter
	*/
	long Distance();
	
	/**
	* Do count measurents and calculate the average. 
	* To avoid defilement from ow/high peaks, min/max values
	* are substracted from the average
	*
	* \param wait delay between measurements, default = DEFAULT_DELAY/ms
	* \param count number of measurements, default DEFAULT_PINGS
	* \return long distance in centimeter
	**/
	long DistanceAvg(int wait=DEFAULT_DELAY, int count=DEFAULT_PINGS);
	
	/**
	* Do only a ping. Get result with methode getDistance()
	* 
	* \param keine
	*/
	void Ping() ;
	
	/**
	* return latest distance. Methode Ping() should be called before
	* \param keine
	* \return Distanz in Zentimeter
	*/
	long getDistance();
	

private:
	/**
	* Do the measurement calculation and return result in centimeter
	* SR04 measure echo time to obstacle and return way. 
	* <br>
	* Sound travels with 340m/sec
	* <br>
	* Example: Obstace 100cm away from SR04. Measure time is 100cm to
	* obstacle and 100cm return = 200cm
	* <br>
	* 1sec = 1000ms = 1.000.000uS
	* 1.000.000 / 340 = Distance in microseconds for 100cm
	* 2941uS fuer 100cm = 5882 uS fuer 200cm
	*
	* duration / 5882 * 100 = distance in cm
	*/	
	long MicrosecondsToCentimeter(long duration);
	
	long _currentDistance;
	int _echoPin, _triggerPin;
	long _duration, _distance;
	bool _autoMode;
};
#endif



