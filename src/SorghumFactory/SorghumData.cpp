#ifdef RAYTRACERFACILITY
#include "BTFMeshRenderer.hpp"
#endif
#include "CBTFGroup.hpp"
#include "CompressedBTF.hpp"
#include "DefaultResources.hpp"
#include "IVolume.hpp"
#include "LeafData.hpp"
#include "PanicleData.hpp"
#include "SorghumData.hpp"
#include "SorghumLayer.hpp"
#include "StemData.hpp"
#ifdef RAYTRACERFACILITY
using namespace RayTracerFacility;
#endif
using namespace PlantArchitect;

void SorghumData::OnCreate() {}

void SorghumData::OnDestroy() {
  m_descriptor.Clear();
  m_meshGenerated = false;
  m_seperated = true;
  m_includeStem = true;
  m_segmentedMask = false;
}

void SorghumData::OnInspect() {
  static const char *SorghumModes[]{"Procedural Growth", "Sorghum State"};
  ImGui::Checkbox("Seperated", &m_seperated);
  ImGui::Checkbox("Include stem", &m_includeStem);
  ImGui::Checkbox("Mask", &m_segmentedMask);
  if (ImGui::Checkbox("Skeleton", &m_skeleton)) {
    FormPlant();
    ApplyGeometry();
  }

  ImGui::Combo("Mode", &m_mode, SorghumModes, IM_ARRAYSIZE(SorghumModes));
  switch ((SorghumMode)m_mode) {
  case SorghumMode::ProceduralSorghum: {
    Editor::DragAndDropButton<ProceduralSorghum>(m_descriptor,
                                                 "Procedural Sorghum");
    auto descriptor = m_descriptor.Get<ProceduralSorghum>();
    if (descriptor) {
      if (ImGui::SliderFloat("Time", &m_currentTime, 0.0f,
                             descriptor->GetCurrentEndTime())) {
        FormPlant();
        ApplyGeometry();
      }
      if (ImGui::Button("Apply")) {
        FormPlant();
        ApplyGeometry();
      }
    }
  } break;
  case SorghumMode::SorghumStateGenerator: {
    Editor::DragAndDropButton<SorghumStateGenerator>(m_descriptor,
                                                     "Sorghum State Generator");
    auto descriptor = m_descriptor.Get<SorghumStateGenerator>();
    bool changed = ImGui::DragInt("Seed", &m_seed);
    if (descriptor) {
      if (ImGui::Button("Apply") || changed) {
        FormPlant();
        ApplyGeometry();
      }
    }
  } break;
  }

  if (m_meshGenerated) {
    if (ImGui::TreeNodeEx("I/O")) {
      FileUtils::SaveFile(
          "Export OBJ", "3D Model", {".obj"},
          [this](const std::filesystem::path &path) {
            ExportModel(path.string());
          },
          false);

      ImGui::TreePop();
    }
    /*
    FileUtils::SaveFile("Export Point cloud", "Point cloud", {".uepc"},
                          [this](const std::filesystem::path &path) {
      auto pointCloud =
          Application::GetLayer<SorghumLayer>()->ScanPointCloud(GetOwner());
      pointCloud->Export(path);
    }, false);
     */
  }
}

void SorghumData::ExportModel(const std::string &filename,
                              const bool &includeFoliage) const {
  std::ofstream of;
  of.open(filename, std::ofstream::out | std::ofstream::trunc);
  if (of.is_open()) {
    std::string start = "#Sorghum field, by Bosheng Li";
    start += "\n";
    of.write(start.c_str(), start.size());
    of.flush();
    unsigned startIndex = 1;
    SorghumLayer::ExportSorghum(GetOwner(), of, startIndex);
    of.close();
    UNIENGINE_LOG("Sorghums saved as " + filename);
  } else {
    UNIENGINE_ERROR("Can't open file!");
  }
}

void SorghumData::Serialize(YAML::Emitter &out) {
  out << YAML::Key << "m_mode" << YAML::Value << m_mode;
  out << YAML::Key << "m_seed" << YAML::Value << m_seed;
  out << YAML::Key << "m_skeleton" << YAML::Value << m_skeleton;
  out << YAML::Key << "m_gravityDirection" << YAML::Value << m_gravityDirection;
  out << YAML::Key << "m_currentTime" << YAML::Value << m_currentTime;
  out << YAML::Key << "m_recordedVersion" << YAML::Value << m_recordedVersion;
  out << YAML::Key << "m_meshGenerated" << YAML::Value << m_meshGenerated;
  out << YAML::Key << "m_seperated" << YAML::Value << m_seperated;
  out << YAML::Key << "m_includeStem" << YAML::Value << m_includeStem;
  out << YAML::Key << "m_segmentedMask" << YAML::Value << m_segmentedMask;
  out << YAML::Key << "m_descriptor" << YAML::BeginMap;
  m_descriptor.Serialize(out);
  out << YAML::EndMap;
}
void SorghumData::Deserialize(const YAML::Node &in) {
  if (in["m_mode"])
    m_mode = in["m_mode"].as<int>();
  if (in["m_seed"])
    m_seed = in["m_seed"].as<int>();

  if (in["m_gravityDirection"])
    m_gravityDirection = in["m_gravityDirection"].as<glm::vec3>();
  if (in["m_meshGenerated"])
    m_meshGenerated = in["m_meshGenerated"].as<bool>();
  if (in["m_currentTime"])
    m_currentTime = in["m_currentTime"].as<float>();
  if (in["m_skeleton"])
    m_skeleton = in["m_skeleton"].as<float>();
  if (in["m_seperated"])
    m_seperated = in["m_seperated"].as<bool>();
  if (in["m_includeStem"])
    m_includeStem = in["m_includeStem"].as<bool>();
  if (in["m_segmentedMask"])
    m_segmentedMask = in["m_segmentedMask"].as<bool>();

  if (in["m_recordedVersion"])
    m_recordedVersion = in["m_recordedVersion"].as<unsigned>();
  if (in["m_descriptor"])
    m_descriptor.Deserialize(in["m_descriptor"]);
}

void SorghumData::CollectAssetRef(std::vector<AssetRef> &list) {
  list.push_back(m_descriptor);
}

void SorghumData::FormPlant(bool doubleFace) {
  SorghumStatePair statePair;
  auto sorghumLayer = Application::GetLayer<SorghumLayer>();
  auto scene = GetScene();
  switch ((SorghumMode)m_mode) {
  case SorghumMode::ProceduralSorghum: {
    auto descriptor = m_descriptor.Get<ProceduralSorghum>();
    if (!descriptor)
      break;
    m_currentTime =
        glm::clamp(m_currentTime, 0.0f, descriptor->GetCurrentEndTime());
    statePair = descriptor->Get(m_currentTime);
    m_recordedVersion = descriptor->GetVersion();
  } break;
  case SorghumMode::SorghumStateGenerator: {
    auto descriptor = m_descriptor.Get<SorghumStateGenerator>();
    if (!descriptor)
      break;
    statePair.m_right = statePair.m_left = descriptor->Generate(m_seed);
    statePair.m_a = 1.0f;
    m_recordedVersion = descriptor->GetVersion();
  } break;
  }

  // 1. Set owner's spline
  auto children = scene->GetChildren(GetOwner());
  for (int i = 0; i < children.size(); i++) {
    scene->DeleteEntity(children[i]);
  }
  auto stem = sorghumLayer->CreateSorghumStem(GetOwner());
  auto stemData = scene->GetOrSetPrivateComponent<StemData>(stem).lock();
  stemData->FormStem(statePair, m_skeleton);
  auto leafSize = statePair.GetLeafSize();
  for (int i = 0; i < leafSize; i++) {
    Entity leaf = sorghumLayer->CreateSorghumLeaf(GetOwner(), i);
    auto leafData = scene->GetOrSetPrivateComponent<LeafData>(leaf).lock();
    leafData->FormLeaf(statePair, m_skeleton, doubleFace);
  }
  auto panicle = sorghumLayer->CreateSorghumPanicle(GetOwner());
  auto panicleData =
      scene->GetOrSetPrivateComponent<PanicleData>(panicle).lock();
  panicleData->FormPanicle(statePair);
}
void SorghumData::ApplyGeometry(bool doubleFace) {
  auto scene = GetScene();
  auto owner = GetOwner();
  auto sorghumLayer = Application::GetLayer<SorghumLayer>();
  bool seperated = m_seperated || m_segmentedMask;
  auto bottomFace = !m_skeleton && !m_segmentedMask && doubleFace;
  if (!seperated) {
    unsigned vertexCount = 0;
    std::vector<UniEngine::Vertex> vertices;
    std::vector<glm::uvec3> triangles;

    scene->ForEachChild(owner, [&](Entity child) {
      if (m_includeStem && scene->HasDataComponent<StemTag>(child)) {
        auto stemData = scene->GetOrSetPrivateComponent<StemData>(child).lock();
        vertices.insert(vertices.end(), stemData->m_vertices.begin(),
                        stemData->m_vertices.end());
        for (const auto &triangle : stemData->m_triangles) {
          triangles.emplace_back(triangle.x + vertexCount,
                                 triangle.y + vertexCount,
                                 triangle.z + vertexCount);
        }
        vertexCount = vertices.size();
      } else if (scene->HasDataComponent<LeafTag>(child)) {
        auto leafData = scene->GetOrSetPrivateComponent<LeafData>(child).lock();
        vertices.insert(vertices.end(), leafData->m_vertices.begin(),
                        leafData->m_vertices.end());
        for (const auto &triangle : leafData->m_triangles) {
          triangles.emplace_back(triangle.x + vertexCount,
                                 triangle.y + vertexCount,
                                 triangle.z + vertexCount);
        }
        vertexCount = vertices.size();

      } else if (scene->HasDataComponent<PanicleTag>(child)) {
        auto panicleData =
            scene->GetOrSetPrivateComponent<PanicleData>(child).lock();
        auto panicleGeometryEntity = scene->CreateEntity(
            sorghumLayer->m_panicleGeometryArchetype, "Panicle Geometry");
        scene->SetParent(panicleGeometryEntity, child);
        auto meshRenderer =
            scene->GetOrSetPrivateComponent<MeshRenderer>(panicleGeometryEntity)
                .lock();
        if (!panicleData->m_vertices.empty()) {
          meshRenderer->m_mesh = ProjectManager::CreateTemporaryAsset<Mesh>();
          meshRenderer->m_mesh.Get<Mesh>()->SetVertices(
              17, panicleData->m_vertices, panicleData->m_triangles);
          meshRenderer->m_material = sorghumLayer->m_panicleMaterial;
        } else {
          meshRenderer->m_mesh.Clear();
        }
      }
    });
    auto leavesGeometryEntity = scene->CreateEntity(
        sorghumLayer->m_leafGeometryArchetype, "Leaves Geometry");
    scene->SetParent(leavesGeometryEntity, owner);
    auto leafTopFaceMeshRenderer =
        scene->GetOrSetPrivateComponent<MeshRenderer>(leavesGeometryEntity)
            .lock();

    if (m_skeleton) {
      auto material = ProjectManager::CreateTemporaryAsset<Material>();
      material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
      leafTopFaceMeshRenderer->m_material = material;
      material->m_materialProperties.m_albedoColor =
          sorghumLayer->m_skeletonColor;
    } else {
      leafTopFaceMeshRenderer->m_material = sorghumLayer->m_leafMaterial;
    }
    if (!vertices.empty()) {
      leafTopFaceMeshRenderer->m_mesh =
          ProjectManager::CreateTemporaryAsset<Mesh>();
      leafTopFaceMeshRenderer->m_mesh.Get<Mesh>()->SetVertices(17, vertices,
                                                               triangles);
    } else {
      leafTopFaceMeshRenderer->m_mesh.Clear();
    }
#ifdef RAYTRACERFACILITY
    auto leafTopFaceBtfMeshRenderer =
        scene->GetOrSetPrivateComponent<BTFMeshRenderer>(leavesGeometryEntity)
            .lock();
    leafTopFaceBtfMeshRenderer->m_mesh = leafTopFaceMeshRenderer->m_mesh;
    auto group = sorghumLayer->m_leafCBTFGroup.Get<CBTFGroup>();
    if(group) {
      leafTopFaceBtfMeshRenderer->m_btf = group->GetRandom();
    }
    if (m_skeleton) {
      leafTopFaceMeshRenderer->SetEnabled(true);
      leafTopFaceBtfMeshRenderer->SetEnabled(false);
    } else {
      leafTopFaceMeshRenderer->SetEnabled(!sorghumLayer->m_enableCompressedBTF);
      leafTopFaceBtfMeshRenderer->SetEnabled(
          sorghumLayer->m_enableCompressedBTF);
    }
#endif
    if (bottomFace) {
      vertexCount = 0;
      vertices.clear();
      triangles.clear();
      scene->ForEachChild(owner, [&](Entity child) {
        if (scene->HasDataComponent<LeafTag>(child)) {
          auto leafData =
              scene->GetOrSetPrivateComponent<LeafData>(child).lock();
          vertices.insert(vertices.end(),
                          leafData->m_bottomFaceVertices.begin(),
                          leafData->m_bottomFaceVertices.end());
          for (const auto &triangle : leafData->m_bottomFaceTriangles) {
            triangles.emplace_back(triangle.x + vertexCount,
                                   triangle.y + vertexCount,
                                   triangle.z + vertexCount);
          }
          vertexCount = vertices.size();
        }
      });
      auto leavesBottomGeometryEntity =
          scene->CreateEntity(sorghumLayer->m_leafBottomFaceGeometryArchetype,
                              "Leaves Bottom Face Geometry");
      scene->SetParent(leavesBottomGeometryEntity, owner);
      auto leafBottomFaceMeshRenderer =
          scene
              ->GetOrSetPrivateComponent<MeshRenderer>(
                  leavesBottomGeometryEntity)
              .lock();
      if (!vertices.empty()) {
        leafBottomFaceMeshRenderer->m_mesh =
            ProjectManager::CreateTemporaryAsset<Mesh>();
        leafBottomFaceMeshRenderer->m_mesh.Get<Mesh>()->SetVertices(
            17, vertices, triangles);
      } else {
        leafBottomFaceMeshRenderer->m_mesh.Clear();
      }
      leafBottomFaceMeshRenderer->m_material =
          sorghumLayer->m_leafBottomFaceMaterial;
#ifdef RAYTRACERFACILITY
      auto leafBottomFaceBtfMeshRenderer =
          scene
              ->GetOrSetPrivateComponent<BTFMeshRenderer>(
                  leavesBottomGeometryEntity)
              .lock();
      leafBottomFaceBtfMeshRenderer->m_mesh =
          leafBottomFaceMeshRenderer->m_mesh;
      auto group = sorghumLayer->m_leafBottomFaceCBTFGroup.Get<CBTFGroup>();
      if(group) {
        leafBottomFaceBtfMeshRenderer->m_btf = group->GetRandom();
      }
      leafBottomFaceMeshRenderer->SetEnabled(
          !sorghumLayer->m_enableCompressedBTF);
      leafBottomFaceBtfMeshRenderer->SetEnabled(
          sorghumLayer->m_enableCompressedBTF);
#endif
    }
  } else {
    int i = 0;
    scene->ForEachChild(owner, [&](Entity child) {
      if (m_includeStem && scene->HasDataComponent<StemTag>(child)) {
        auto stemData = scene->GetOrSetPrivateComponent<StemData>(child).lock();
        auto stemGeometryEntity = scene->CreateEntity(
            sorghumLayer->m_stemGeometryArchetype, "Stem Geometry");
        scene->SetParent(stemGeometryEntity, child);
        auto meshRenderer =
            scene->GetOrSetPrivateComponent<MeshRenderer>(stemGeometryEntity)
                .lock();
        if (!stemData->m_vertices.empty()) {
          meshRenderer->m_mesh = ProjectManager::CreateTemporaryAsset<Mesh>();
          meshRenderer->m_mesh.Get<Mesh>()->SetVertices(
              17, stemData->m_vertices, stemData->m_triangles);
        } else {
          meshRenderer->m_mesh.Clear();
        }

        if (m_segmentedMask) {
          auto material = ProjectManager::CreateTemporaryAsset<Material>();
          material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
          meshRenderer->m_material = material;
          material->m_drawSettings.m_cullFace = false;
          material->m_materialProperties.m_albedoColor =
              stemData->m_vertexColor;
          material->m_materialProperties.m_roughness = 1.0f;
          material->m_materialProperties.m_metallic = 0.0f;
        } else if (m_skeleton) {
          auto material = ProjectManager::CreateTemporaryAsset<Material>();
          material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
          meshRenderer->m_material = material;
          material->m_materialProperties.m_albedoColor =
              sorghumLayer->m_skeletonColor;
        } else {
          meshRenderer->m_material = sorghumLayer->m_leafMaterial;
        }
#ifdef RAYTRACERFACILITY
        auto btfMeshRenderer =
            scene->GetOrSetPrivateComponent<BTFMeshRenderer>(stemGeometryEntity)
                .lock();
        btfMeshRenderer->m_mesh = meshRenderer->m_mesh;
        auto group = sorghumLayer->m_leafCBTFGroup.Get<CBTFGroup>();
        if(group) {
          btfMeshRenderer->m_btf = group->GetRandom();
        }
        if (m_skeleton || m_segmentedMask) {
          meshRenderer->SetEnabled(true);
          btfMeshRenderer->SetEnabled(false);
        } else {
          meshRenderer->SetEnabled(!sorghumLayer->m_enableCompressedBTF);
          btfMeshRenderer->SetEnabled(sorghumLayer->m_enableCompressedBTF);
        }
#endif
      } else if (scene->HasDataComponent<LeafTag>(child)) {
        auto leafData = scene->GetOrSetPrivateComponent<LeafData>(child).lock();
        auto leafTopFaceGeometryEntity = scene->CreateEntity(
            sorghumLayer->m_leafGeometryArchetype, "Leaf Top Face Geometry");
        scene->SetParent(leafTopFaceGeometryEntity, child);
        auto leafTopFaceMeshRenderer =
            scene
                ->GetOrSetPrivateComponent<MeshRenderer>(
                    leafTopFaceGeometryEntity)
                .lock();
        if (!leafData->m_vertices.empty()) {
          leafTopFaceMeshRenderer->m_mesh =
              ProjectManager::CreateTemporaryAsset<Mesh>();
          leafTopFaceMeshRenderer->m_mesh.Get<Mesh>()->SetVertices(
              17, leafData->m_vertices, leafData->m_triangles);
        } else {
          leafTopFaceMeshRenderer->m_mesh.Clear();
        }
        if (m_segmentedMask) {
          auto material = ProjectManager::CreateTemporaryAsset<Material>();
          leafTopFaceMeshRenderer->m_material = material;
          material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
          material->m_drawSettings.m_cullFace = false;
          material->m_materialProperties.m_albedoColor =
              leafData->m_vertexColor;
          material->m_materialProperties.m_roughness = 1.0f;
          material->m_materialProperties.m_metallic = 0.0f;
        } else if (m_skeleton) {
          auto material = ProjectManager::CreateTemporaryAsset<Material>();
          material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
          leafTopFaceMeshRenderer->m_material = material;
          material->m_materialProperties.m_albedoColor =
              sorghumLayer->m_skeletonColor;
        } else {
          leafTopFaceMeshRenderer->m_material = sorghumLayer->m_leafMaterial;
        }
#ifdef RAYTRACERFACILITY
        auto leafTopFaceBtfMeshRenderer =
            scene
                ->GetOrSetPrivateComponent<BTFMeshRenderer>(
                    leafTopFaceGeometryEntity)
                .lock();
        leafTopFaceBtfMeshRenderer->m_mesh = leafTopFaceMeshRenderer->m_mesh;
        auto group = sorghumLayer->m_leafCBTFGroup.Get<CBTFGroup>();
        if(group) {
          leafTopFaceBtfMeshRenderer->m_btf = group->GetRandom();
        }
        if (m_skeleton || m_segmentedMask) {
          leafTopFaceMeshRenderer->SetEnabled(true);
          leafTopFaceBtfMeshRenderer->SetEnabled(false);
        } else {
          leafTopFaceMeshRenderer->SetEnabled(
              !sorghumLayer->m_enableCompressedBTF);
          leafTopFaceBtfMeshRenderer->SetEnabled(
              sorghumLayer->m_enableCompressedBTF);
        }
#endif
        if (bottomFace) {
          auto leafBottomFaceGeometryEntity = scene->CreateEntity(
              sorghumLayer->m_leafBottomFaceGeometryArchetype,
              "Leaf Bottom Face Geometry");
          scene->SetParent(leafBottomFaceGeometryEntity, child);
          auto leafBottomFaceMeshRenderer =
              scene
                  ->GetOrSetPrivateComponent<MeshRenderer>(
                      leafBottomFaceGeometryEntity)
                  .lock();
          if (!leafData->m_bottomFaceVertices.empty()) {
            leafBottomFaceMeshRenderer->m_mesh =
                ProjectManager::CreateTemporaryAsset<Mesh>();
            leafBottomFaceMeshRenderer->m_mesh.Get<Mesh>()->SetVertices(
                17, leafData->m_bottomFaceVertices,
                leafData->m_bottomFaceTriangles);
          } else {
            leafBottomFaceMeshRenderer->m_mesh.Clear();
          }
          leafBottomFaceMeshRenderer->m_material =
              Application::GetLayer<SorghumLayer>()->m_leafBottomFaceMaterial;
#ifdef RAYTRACERFACILITY
          auto leafBottomFaceBtfMeshRenderer =
              scene
                  ->GetOrSetPrivateComponent<BTFMeshRenderer>(
                      leafBottomFaceGeometryEntity)
                  .lock();
          leafBottomFaceBtfMeshRenderer->m_mesh =
              leafBottomFaceMeshRenderer->m_mesh;
          auto group = sorghumLayer->m_leafBottomFaceCBTFGroup.Get<CBTFGroup>();
          if(group) {
            leafBottomFaceBtfMeshRenderer->m_btf = group->GetRandom();
          }
          leafBottomFaceMeshRenderer->SetEnabled(
              !sorghumLayer->m_enableCompressedBTF);
          leafBottomFaceBtfMeshRenderer->SetEnabled(
              sorghumLayer->m_enableCompressedBTF);
#endif
        }
      } else if (scene->HasDataComponent<PanicleTag>(child)) {
        auto panicleData =
            scene->GetOrSetPrivateComponent<PanicleData>(child).lock();
        auto panicleGeometryEntity = scene->CreateEntity(
            sorghumLayer->m_panicleGeometryArchetype, "Panicle Geometry");
        scene->SetParent(panicleGeometryEntity, child);
        auto meshRenderer =
            scene->GetOrSetPrivateComponent<MeshRenderer>(panicleGeometryEntity)
                .lock();
        if (!panicleData->m_vertices.empty()) {
          meshRenderer->m_mesh = ProjectManager::CreateTemporaryAsset<Mesh>();
          meshRenderer->m_mesh.Get<Mesh>()->SetVertices(
              17, panicleData->m_vertices, panicleData->m_triangles);
        } else {
          meshRenderer->m_mesh.Clear();
        }
        if (m_segmentedMask) {
          auto material = ProjectManager::CreateTemporaryAsset<Material>();
          meshRenderer->m_material = material;
          material->SetProgram(DefaultResources::GLPrograms::StandardProgram);
          material->m_drawSettings.m_cullFace = false;
          material->m_materialProperties.m_albedoColor = glm::vec3(0.0f);
          material->m_materialProperties.m_roughness = 1.0f;
          material->m_materialProperties.m_metallic = 0.0f;
        } else {
          meshRenderer->m_material =
              Application::GetLayer<SorghumLayer>()->m_panicleMaterial;
        }
      }
      i++;
    });
  }
  m_meshGenerated = true;
}

void SorghumData::SetTime(float time) {
  m_currentTime = time;
  FormPlant();
}
