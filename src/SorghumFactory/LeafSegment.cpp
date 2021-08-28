#include <LeafSegment.hpp>

using namespace SorghumFactory;

LeafSegment::LeafSegment(glm::vec3 position, glm::vec3 up, glm::vec3 front,
                         float leafHalfWidth, float theta, bool isLeaf,
                         float surfacePush, float leftFlatness,
                         float rightFlatness, float leftFlatnessFactor,
                         float rightFlatnessFactor) {
  m_isLeaf = isLeaf;
  m_position = position;
  m_up = up;
  m_front = front;
  m_leafHalfWidth = leafHalfWidth;
  m_theta = theta;
  m_surfacePush = surfacePush;
  if (isLeaf) {
    m_leftFlatness = leftFlatness;
    m_rightFlatness = rightFlatness;
    m_leftFlatnessFactor = leftFlatnessFactor;
    m_rightFlatnessFactor = rightFlatnessFactor;
  }
  m_radius = m_leafHalfWidth;
}

glm::vec3 LeafSegment::GetPoint(float angle) {
  if (m_theta < 90.0f) {
    const auto radius = m_leafHalfWidth / glm::sin(glm::radians(m_theta));
    const auto distanceToCenter =
        radius * glm::cos(glm::radians(glm::abs(angle)));
    const auto actualHeight =
        (radius -
         distanceToCenter) * (angle < 0 ? m_leftFlatness : m_rightFlatness);
    const auto center =
        m_position + (radius - m_radius * (1.0f - m_surfacePush)) * m_up;
    const auto direction = glm::rotate(m_up, glm::radians(angle), m_front);
    float compressFactor =
        glm::pow(actualHeight / m_radius,
                 angle < 0 ? m_leftFlatnessFactor : m_rightFlatnessFactor);
    if (glm::isnan(compressFactor)) {
      compressFactor = 0.0f;
    }
    return center - radius * direction - actualHeight * compressFactor * m_up;
  }
  const auto direction = glm::rotate(m_up, glm::radians(angle), m_front);
  return m_position - m_radius * direction;
}
