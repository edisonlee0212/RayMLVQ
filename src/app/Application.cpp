// PlantFactory.cpp : This file contains the 'main' function. Program execution
// begins and ends there.
//
#include <Application.hpp>
#ifdef RAYTRACERFACILITY
#include <RayTracerLayer.hpp>
#endif

#include <ClassRegistry.hpp>
#include <ObjectRotator.hpp>
#include <PhysicsLayer.hpp>
#include <SorghumLayer.hpp>

#include <AutoSorghumGenerationPipeline.hpp>
#include <GeneralDataCapture.hpp>
#include <SorghumStateGenerator.hpp>
#include "PointCloudCapture.hpp"
#include "IlluminationEstimation.hpp"
using namespace Scripts;
using namespace SorghumFactory;
#ifdef RAYTRACERFACILITY
using namespace RayTracerFacility;
#endif

int main() {
  ClassRegistry::RegisterPrivateComponent<AutoSorghumGenerationPipeline>(
      "AutoSorghumGenerationPipeline");
  ClassRegistry::RegisterPrivateComponent<IlluminationEstimation>(
      "IlluminationEstimation");
  ClassRegistry::RegisterAsset<GeneralDataCapture>("GeneralDataCapture",
                                                   ".gdc");
  ClassRegistry::RegisterAsset<PointCloudCapture>("PointCloudCapture",
                                                  ".pcc");
  ClassRegistry::RegisterPrivateComponent<ObjectRotator>("ObjectRotator");

  ApplicationConfigs applicationConfigs;
  Application::Create(applicationConfigs);
#ifdef RAYTRACERFACILITY
  Application::PushLayer<RayTracerLayer>();
#endif
  Application::PushLayer<SorghumLayer>();
#pragma region Engine Loop
  Application::Start();
#pragma endregion

  Application::End();
}
