/*
	cage
	
	Automated reptile tank environment control. Manages temperature
	and humidity through use of sensors, mister, heat source, fans.
	
	LCD:
	* LCD RS pin (4) -> d5
	* LCD Enable pin (6) -> d4
	* LCD D4 pin (11) -> d3
	* LCD D5 pin (12) -> d2
	* LCD D6 pin (14) -> d1
	* LCD D7 pin (13) -> d0
	* LCD R/W pin (5) to ground
	* 10K pot:
	* ends to +5V and 1k -> ground
	* wiper to LCD VO pin (3)
	
	Controls:
	* Up button -> d8
	* Down button -> d7
	* Enter button -> d6
	
	Sensors:
	* DHTPIN -> A0
	* lightPin -> A1
	
	Actuators:
	* Cool -> d12
	* Heater -> d11
	* Fan -> d13
	* Mister -> d9
	* Lamp (outlet) -> d10

	TODO:
	invert selected setting while changing
	Add second sensor?
	Determine light sensor scaling. Adjust default threshold.	
	make light icon
	add light status to LCD
*/

#include "DHT.h"
#include <LiquidCrystal.h>

#define DHTPIN A0
#define DHTTYPE DHT11
#define LCDLINES 2
#define LCDCHARS 20

DHT dht(DHTPIN, DHTTYPE);

LiquidCrystal lcd(5, 4, 3, 2, 1, 0);
const int upPin = 8;
const int downPin = 7;
const int enterPin = 6;

const int temp1Pin = DHTPIN;
const int lightPin = A1;

const int coolPin = 12;
const int heatPin = 11;
const int fanPin = 13;
const int mistPin = 9;
const int lampPin = 10;

bool hot = 0;
bool cold = 0;
bool dry = 0;
bool wet = 0;
bool light = 0;

int setting[3] = {70, 30, 90, 60, 50}; // templow, humlow, temphi, humhi, light
float current[3] = {75, 50, 50};

long lastAction = 0;
long actionDelay = 3000; // delay in ms
long lastDebounce = 0;
long debounceDelay = 100;

// percent (0.0 - 1.0) under-/overshoot before turning on/off
float hyst = .03; 

// menu timeout in ms
long timeout = 15000;

void setup() {
	dht.begin();

	// configure display
	lcd.begin(LCDCHARS,LCDLINES);
	lcd.clear();
	for (int i = 0; i < LCDLINES; i++) {
		lcd.setCursor(11, i);
		lcd.print("--");
	}	

	// configure buttons
	pinMode(upPin, INPUT);
	pinMode(downPin, INPUT);
	pinMode(enterPin, INPUT);
	
	// configure actuators
	pinMode(heatPin, OUTPUT);
	pinMode(fanPin, OUTPUT);
	pinMode(mistPin, OUTPUT);
	
	// configure sensors
	pinMode(temp1Pin, INPUT);
}

void loop() {
	acquire();
	show();
	adjust();

	if (debounce(enterPin))
		menu();
}

void acquire() {
	float t = dht.readTemperature();
	float h = dht.readHumidity();

	if (isnan(t) || isnan(h))
		return;
	else {
		current[0] = t;
		current[1] = h;
	}

	current[3] = analogRead(lightPin);
}

void adjust() {
	int heatPoint = setting[0] - setting[0] * hyst;
	int heatStop  = setting[0] + setting[0] * hyst;
	int coolPoint = setting[2] + setting[2] * hyst;
	int coolStop  = setting[2] - setting[2] * hyst;
	int mistPoint = setting[1] - setting[1] * hyst;
	int mistStop  = setting[1] + setting[1] * hyst;
	int dryPoint  = setting[3] + setting[3] * hyst;
	int dryStop   = setting[3] - setting[3] * hyst;
	int lightPoint = setting[4] + setting[4] * hyst;
	int darkPoint = setting[4] - setting[4] * hyst;

	if ((millis() - lastAction) > actionDelay) {
		lcd.setCursor(9, 0);
		if (current[0] < heatPoint ) {
			// too cold. turn on heater.
			lcd.print("^^");
			cold = 1;
		}
		else if (cold == 1 && current[0] > heatStop) {
			// temp is good. turn off heater.
			lcd.print("--");
			cold = 0;
		}
		
		if (current[0] > coolPoint) {
			// too warm. turn on fan.
			lcd.print("vv");
			hot = 1;
		}
		else if (hot == 1 && current[0] < coolStop) {
			// temp is good. turn off fan.
			lcd.print("--");
			hot = 0;
		}

		if (current[3] > lightPoint)
			// bright outside. turn on lamp.
			light = 1;
		else if (current[3] < darkPoint)
			// dark outside. turn off lamp.
			light = 0;
		}
		
		lcd.setCursor(11, 1);
		if (current[1] < mistPoint) {
			// too dry. turn on mist.
			lcd.print("^^");
			dry = 1;
		}
		else if (current[1] > dryPoint) {
			// too wet. turn on fan.
			lcd.print("vv");
			wet = 1;
		}
		else if (current[1] > mistStop) {
			// hum is good. turn off mist.
			lcd.print("--");
			dry = 0;
		}
		else if (current[1] < dryStop) {
			// hum is good. turn off fan.
			lcd.print("--");
			wet = 0;
		}

		if (cold == 1)
			digitalWrite(heatPin, HIGH);
		else
			digitalWrite(heatPin, LOW);
		if (hot == 1 || wet == 1)
			digitalWrite(fanPin, HIGH);
		else
			digitalWrite(fanPin, LOW);
		if (dry == 1)
			digitalWrite(mistPin, HIGH);
		else
			digitalWrite(mistPin, LOW);
		if (light == 1)
			digitalWrite(lampPin, HIGH);
		else
			digitalWrite(lampPin, LOW);
		
		lastAction = millis();
	}
}

void change(int selected) {
	long lastClick = millis();
	int old = setting[selected];
	while (millis() < lastClick + timeout) {
		if (debounce(upPin)) {
			setting[selected]++;
			lastClick = millis();
		}
		if (debounce(downPin)) {
			setting[selected]--;
			lastClick = millis();
		}
		show();
		if (debounce(enterPin))
			break;
	}
	if (millis() > lastClick + timeout)
		setting[selected] = old;
	lastAction -= actionDelay;
}

int debounce(int pin) {
	if (digitalRead(pin)) {
		delay(debounceDelay);
		if (digitalRead(pin))
			return true;
		else
			return false;
	}
	else
		return false;
}

void menu() {
	int selected = 0;
	long lastClick = millis();

	while (millis() < lastClick + timeout) {
		lcd.setCursor(18, selected);
		lcd.print("<");
		
	if (debounce(downPin) || debounce(upPin)) {
			lcd.setCursor(18, selected);
			lcd.print(" ");
			selected = !selected;
			lastClick = millis();
		}
		
	if (debounce(enterPin)) {
			lcd.setCursor(18, selected);
			lcd.print("*");
			change(selected);
			break;
		}
	}
	for (int i = 0; i < LCDLINES; i++) {
		lcd.setCursor(18, i);
		lcd.print(" ");
	}
}

void show() {
	lcd.setCursor(1,0);
	lcd.print(char(223));
	lcd.setCursor(2,0);
	lcd.print("F:");
	lcd.setCursor(0,1);
	lcd.print("%RH:");
	
	int readingPos;
	int settingPos[4];

	// set display positions
	for (int i = 0; i < 2; i++) {
		if (current[i] > 99)
			readingPos = 5;
		else
			readingPos = 6;

		if (setting[i] > 99)
			settingPos[0] = 11;
		else
			settingPos[0] = 12;

		settingPos[1] = 15;

		lcd.clear()
		lcd.setCursor(readingPos[0], i);
		lcd.print((int) current[i]);
		lcd.setCursor(settingPos[1], i);
		lcd.print(setting[i]);
		lcd.print("-");
		lcd.print(setting[i+2]);
	}
}
