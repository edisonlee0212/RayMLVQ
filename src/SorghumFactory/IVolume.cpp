#include <IVolume.hpp>
glm::vec3 EcoSysLab::SphericalVolume::GetRandomPoint() {
  return glm::ballRand(1.0f) * m_radius;
}
bool EcoSysLab::SphericalVolume::InVolume(
    const GlobalTransform &globalTransform, const glm::vec3 &position) {
  return false;
}
bool EcoSysLab::SphericalVolume::InVolume(const glm::vec3 &position) {
  auto relativePosition = glm::vec3(position.x / m_radius.x, position.y / m_radius.y, position.z / m_radius.z);
  return glm::length(relativePosition) <= 1.0f;
}
