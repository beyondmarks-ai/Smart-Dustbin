#pragma once
#include <Arduino.h>
#include <WebServer.h>
void setupCameraLocation(WebServer &server);
String cameraLocationJson();
bool authorizeCameraSetup(WebServer &server);
String cameraRecoveryPassword();
void printCameraSetupCode();
