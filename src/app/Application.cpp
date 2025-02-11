// PlantFactory.cpp : This file contains the 'main' function. Program execution
// begins and ends there.
//
#include <Application.hpp>
#ifdef RAYTRACERFACILITY
#include <RayTracerLayer.hpp>
#include "CBTFImporter.hpp"
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
using namespace EcoSysLab;
#ifdef RAYTRACERFACILITY
using namespace RayTracerFacility;
#endif

int main() {
  ClassRegistry::RegisterPrivateComponent<AutoSorghumGenerationPipeline>(
      "AutoSorghumGenerationPipeline");
#ifdef RAYTRACERFACILITY
  ClassRegistry::RegisterAsset<IlluminationEstimationPipeline>(
      "IlluminationEstimationPipeline", {".iep"});
  ClassRegistry::RegisterAsset<GeneralDataCapture>("GeneralDataCapture",
                                                   {".gdc"});
  ClassRegistry::RegisterPrivateComponent<CBTFImporter>("CBTFImporter");
#endif
  ClassRegistry::RegisterAsset<PointCloudCapture>("PointCloudCapture",
                                                  {".pcc"});
  ClassRegistry::RegisterPrivateComponent<ObjectRotator>("ObjectRotator");

  ApplicationConfigs applicationConfigs;
  applicationConfigs.m_applicationName = "Sorghum Factory";
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
