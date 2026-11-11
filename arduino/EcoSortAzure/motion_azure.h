#pragma once
#include <Arduino.h>
void setupMotionAzure();
void serviceMotionAzure();
bool triggerAzureCapture();
String azureStatusJson();
String azureProgressJson();
bool azureCaptureBusy();
