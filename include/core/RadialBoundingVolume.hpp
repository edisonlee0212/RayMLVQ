#pragma once
#include <Volume.hpp>
using namespace UniEngine;
namespace PlantFactory {
struct RadialBoundingVolumeSlice {
  float m_maxDistance;
};

class RadialBoundingVolume : public Volume {
  std::vector<std::shared_ptr<Mesh>> m_boundMeshes;
  bool m_meshGenerated = false;

public:
  glm::vec3 m_center;
  float m_sphereRadius;
  glm::vec4 m_displayColor = glm::vec4(0.0f, 0.0f, 1.0f, 0.5f);
  bool m_display = false;
  bool m_pruneBuds = false;
  [[nodiscard]] glm::vec3 GetRandomPoint() override;
  [[nodiscard]] glm::ivec2 SelectSlice(glm::vec3 position) const;
  float m_maxHeight = 0.0f;
  float m_maxRadius = 0.0f;
  void GenerateMesh();
  void FormEntity();
  std::string Save();
  void ExportAsObj(const std::string &filename);
  void Load(const std::string &path);
  float m_displayScale = 0.2f;
  int m_layerAmount = 8;
  int m_sectorAmount = 8;
  std::vector<std::vector<RadialBoundingVolumeSlice>> m_layers;
  void CalculateVolume();
  void CalculateVolume(float maxHeight);
  bool m_displayPoints = true;
  bool m_displayBounds = true;
  Bound m_minMaxBound;
  void OnGui() override;
  bool InVolume(const GlobalTransform& globalTransform, const glm::vec3 &position) override;
  bool InVolume(const glm::vec3 &position) override;
};
} // namespace PlantFactory
