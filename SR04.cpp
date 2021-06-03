
#include "SR04.h"

SR04::SR04(int echoPin, int triggerPin) {
    _echoPin = echoPin;
    _triggerPin = triggerPin;
    pinMode(_echoPin, INPUT);
    pinMode(_triggerPin, OUTPUT);
    _autoMode = false;
    _distance = 999;
}


long SR04::Distance() {
    long d = 0;
    _duration = 0;
    digitalWrite(_triggerPin, LOW);
    delayMicroseconds(2);
    digitalWrite(_triggerPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(_triggerPin, LOW);
    delayMicroseconds(2);
    _duration = pulseIn(_echoPin, HIGH, PULSE_TIMEOUT);
    d = MicrosecondsToCentimeter(_duration);
    delay(25);
    return d;
}

long SR04::DistanceAvg(int wait, int count) {
    long min, max, avg, d;
    min = 999;
    max = 0;
    avg = d = 0;

    if (wait < 25) {
        wait = 25;
    }

    if (count < 1) {
        count = 1;
    }

    for (int x = 0; x < count + 2; x++) {
        d = Distance();

        if (d < min) {
            min = d;
        }

        if (d > max) {
            max = d;
        }

        avg += d;
    }

    // substract highest and lowest value
    avg -= (max + min);
    // calculate average
    avg /= count;
    return avg;
}

void SR04::Ping() {
    _distance = Distance();
}

long SR04::getDistance() {
    return _distance;
}

long SR04::MicrosecondsToCentimeter(long duration) {
    long d = (duration * 100) / 5882;
    //d = (d == 0)?999:d;
    return d;
}




