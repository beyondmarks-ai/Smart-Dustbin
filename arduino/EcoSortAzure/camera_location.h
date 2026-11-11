#pragma once
#include <Arduino.h>
#include <WebServer.h>
void setupCameraLocation(WebServer &server);
void serviceCameraPairing();
void pushCameraStatus(const String &status);
String cameraLocationJson();
bool authorizeCameraSetup(WebServer &server);
String cameraRecoveryPassword();
void printCameraSetupCode();
