// PlantFactory.cpp : This file contains the 'main' function. Program execution
// begins and ends there.
//
#include <Application.hpp>
#ifdef RAYTRACERFACILITY
#include "RayTracerCamera.hpp"
#include <RayTracerLayer.hpp>
#endif
#include <ClassRegistry.hpp>
#include <Editor.hpp>
#include <ObjectRotator.hpp>
#include <PhysicsLayer.hpp>
#include <PostProcessing.hpp>
#include <ProjectManager.hpp>
#include <SorghumLayer.hpp>

#include "PointCloudCapture.hpp"
#include <AutoSorghumGenerationPipeline.hpp>
#include <DepthCamera.hpp>
#include <GeneralDataCapture.hpp>
using namespace Scripts;
using namespace SorghumFactory;
#ifdef RAYTRACERFACILITY
using namespace RayTracerFacility;
#endif

void EngineSetup();

int main() {
  ClassRegistry::RegisterPrivateComponent<AutoSorghumGenerationPipeline>(
      "AutoSorghumGenerationPipeline");
  ClassRegistry::RegisterAsset<GeneralDataCapture>("GeneralDataCapture",
                                               ".sdfdatacapture");
  ClassRegistry::RegisterAsset<PointCloudCapture>("PointCloudCapture",
                                                  ".pointCloudCapture");
  ClassRegistry::RegisterPrivateComponent<ObjectRotator>("ObjectRotator");

  EngineSetup();

  ApplicationConfigs applicationConfigs;
  applicationConfigs.m_projectPath = "Datasets/sample.ueproj";
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

void EngineSetup() {
  ProjectManager::SetScenePostLoadActions([=]() {
#pragma region Engine Setup
    Transform transform;
    transform.SetEulerRotation(glm::radians(glm::vec3(150, 30, 0)));

#pragma region Preparations
    Application::Time().SetTimeStep(0.016f);
    transform = Transform();
    transform.SetPosition(glm::vec3(0, 2, 35));
    transform.SetEulerRotation(glm::radians(glm::vec3(15, 0, 0)));
    auto mainCamera =
        Entities::GetCurrentScene()->m_mainCamera.Get<UniEngine::Camera>();
    if (mainCamera) {
      auto postProcessing = mainCamera->GetOwner()
                                .GetOrSetPrivateComponent<PostProcessing>()
                                .lock();
      auto ssao = postProcessing->GetLayer<SSAO>().lock();
      ssao->m_kernelRadius = 0.1;
      mainCamera->GetOwner().SetDataComponent(transform);
      mainCamera->m_useClearColor = true;
      mainCamera->m_clearColor = glm::vec3(0.5f);
    }
#pragma endregion
#pragma endregion
    /*
    const Entity lightEntity = Entities::CreateEntity("Light source");
    auto pointLight = lightEntity.GetOrSetPrivateComponent<PointLight>().lock();
    pointLight->m_diffuseBrightness = 6;
    pointLight->m_lightSize = 0.25f;
    pointLight->m_quadratic = 0.0001f;
    pointLight->m_linear = 0.01f;
    pointLight->m_lightSize = 0.08f;
    transform.SetPosition(glm::vec3(0, 30, 0));
    transform.SetEulerRotation(glm::radians(glm::vec3(0, 0, 0)));
    lightEntity.SetDataComponent(transform);
    */

    auto sdfEntity =
        Entities::CreateEntity(Entities::GetCurrentScene(), "GeneralDataPipeline");
    auto pipeline =
        sdfEntity.GetOrSetPrivateComponent<AutoSorghumGenerationPipeline>()
            .lock();
    auto capture = AssetManager::CreateAsset<GeneralDataCapture>();
    pipeline->m_pipelineBehaviour = capture;

    auto rayTracerCamera = mainCamera->GetOwner()
                               .GetOrSetPrivateComponent<RayTracerCamera>()
                               .lock();
    capture->m_rayTracerCamera = rayTracerCamera;
    rayTracerCamera->SetMainCamera(true);

    auto pointCloudCaptureEntity = Entities::CreateEntity(
        Entities::GetCurrentScene(), "PointCloudPipeline");
    auto pointCloudPipeline =
        pointCloudCaptureEntity
            .GetOrSetPrivateComponent<AutoSorghumGenerationPipeline>()
            .lock();
    auto pointCloudCapture = AssetManager::CreateAsset<PointCloudCapture>();
    pointCloudPipeline->m_pipelineBehaviour = pointCloudCapture;
  });
}
