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
	* LCD R/W pin (5) -> ground
	* LCD VSS (1) -> +3-5v
	* LCD VDD (2) -> gnd
	* 10K pot:
	*	 ends to +5V and 1k -> ground
	*	 wiper to LCD VO pin (3)
	
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
	Add second sensor?
	fix corrupted light icon
	expand sanity check to disallow hi/lo settings to cross

*/

#include <LiquidCrystal.h>
#include "DHT.h"

#define DHTPIN 14 //A0
#define DHTTYPE DHT11
#define LCDLINES 2
#define LCDCHARS 20
#define LDRMIN  100 // light sensor min reading
#define LDRMAX 1020 // light sensor max reading

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

int selected = 0;
int setting[5] = {25, 30, 30, 60, 50}; // templow, temphi, humlow, humhi, light
float current[3] = {25, 50, 50}; // temp, hum, light
int setPos[4] = {11, 14, 11, 14}; // low set, high set
int statusPos = 8;

long lastAction = 0;
long actionDelay = 3000; // delay in ms
long lastDebounce = 0;
long debounceDelay = 100;

// percent (0.0 - 1.0) under-/overshoot before turning on/off
float hyst = .03; 

// menu timeout in ms
long timeout = 15000;

byte lampOn[8] = {
	B00000,
	B01101,
	B01100,
	B00001,
	B10100,
	B00000,
	B00000,
	B00000,
};

byte lampOff[8] = {
	B11111,
	B11101,
	B11100,
	B11000,
	B00001,
	B10011,
	B11111,
	B11111,
};

void setup() {
	dht.begin();
	lcd.createChar(0, lampOn);
	lcd.createChar(1, lampOff);

	// configure display
	lcd.begin(LCDCHARS,LCDLINES);
	lcd.clear();
	for (int i = 0; i < LCDLINES; i++) {
		lcd.setCursor(statusPos, i);
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
	show(0);
	adjust();

	for (int i = 0; i < 1000; i++) {
		if (debounce(enterPin))
			menu();
	}
}

void acquire() {
	float t = dht.readTemperature();
	float h = dht.readHumidity();
	float l = analogRead(lightPin);

	if (isnan(t) || isnan(h))
		return;
	else {
		current[0] = t;
		current[1] = h;
	}

	current[2] = 100 * (l - (LDRMIN)) / (LDRMAX - LDRMIN);
}

void adjust() {
	float heatPoint = setting[0] - setting[0] * hyst;
	float heatStop  = setting[0] + setting[0] * hyst;
	float coolPoint = setting[1] + setting[1] * hyst;
	float coolStop  = setting[1] - setting[1] * hyst;
	float mistPoint = setting[2] - setting[2] * hyst;
	float mistStop  = setting[2] + setting[2] * hyst;
	float dryPoint  = setting[3] + setting[3] * hyst;
	float dryStop   = setting[3] - setting[3] * hyst;
	float lightPoint = setting[4] + setting[4] * hyst;
	float darkPoint = setting[4] - setting[4] * hyst;
	if ((millis() - lastAction) > actionDelay) {
		lcd.setCursor(statusPos, 0);
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

		if (current[2] > lightPoint)
			// bright outside. turn on lamp.
			light = 1;
		else if (current[2] < darkPoint)
			// dark outside. turn off lamp.
			light = 0;

		lcd.setCursor(statusPos, 1);
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

void change() {
	long lastClick = millis();
	int old = setting[selected];
	bool flash = 0;

	while (millis() < lastClick + timeout) {
		if (debounce(upPin)) {
			setting[selected]++;
			lastClick = millis();
		}
		if (debounce(downPin)) {
			setting[selected]--;
			lastClick = millis();
		}
		// setting sanity check
		if (setting[selected] < 0)
			setting[selected] = 0;
		else if (setting[selected] > 99)
			setting[selected] = 99;

		show(1);

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

// properly display 1-, 2-, or 3-digit numbers
void disp(int num, int col, int row) {
	lcd.setCursor(col, row);
	if (num < 10)
		lcd.print(" ");
	lcd.print(num);
}

void menu() {
	long lastClick = millis();
	int selPos = setPos[0] + 2;
	selected = 0;
	int row = 0;

	show(1);
	while (millis() < lastClick + timeout) {
		lcd.setCursor(0, 0);
	//	lcd.print(selected);
		row = selected / 2;

		// clear indicator
		for (int i = 0; i < 2; i++) {
			lcd.setCursor(selPos, i);
			lcd.print("-");
		}
		lcd.setCursor(17, 0);
		lcd.print("-");

		// set indicator
		lcd.setCursor(selPos, row);
		if (selected == 4)
		{
			lcd.setCursor(17, 0);
			lcd.print(">");
	//		disp(setting[4], 17, 1);
		}
		else if (selected % 2)
			lcd.print(">");
		else
			lcd.print("<");

		if (debounce(downPin)) {
			selected = ++selected % 5;
			lastClick = millis();
		}
		if (debounce(upPin)) {
			if (--selected < 0)
				selected = 4;
			lastClick = millis();
		}

		if (debounce(enterPin)) {
			change();
			break;
		}
	}
	// clear indicator
	for (int i = 0; i < 2; i++) {
		lcd.setCursor(selPos, i);
		lcd.print("-");
	}
	lcd.setCursor(17, 0);
	lcd.print(" ");
}

void show(bool setFlag) {
	lcd.setCursor(1,0);
	lcd.print(char(223));
	lcd.setCursor(2,0);
	lcd.print("C:");
	lcd.setCursor(0,1);
	lcd.print("%RH:");

	// set display positions

	int line = 0;
	for (int i = 0; i < 4; i++) {
		disp(setting[i], setPos[i], line);
		if (not (i % 2) && not setFlag)
			lcd.print("-");
		if (i == 1)
			line++;
	}

	// display light status and reading

	lcd.setCursor(18, 0);
	if (light)
		lcd.write(0);
	else
		lcd.write(1);

	if (setFlag)
		disp (setting[4], 17, 1);
	else
		disp((int) current[2], 17, 1);

	int rdgPos = 5;
	for (int i = 0; i < 2; i++)
		disp((int) current[i], rdgPos, i);
}
