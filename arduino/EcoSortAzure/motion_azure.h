#pragma once
#include <Arduino.h>
void setupMotionAzure();
void serviceMotionAzure();
bool triggerAzureCapture();
String azureStatusJson();
bool azureCaptureBusy();
