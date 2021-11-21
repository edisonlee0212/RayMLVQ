#pragma once
#include <ICurve.hpp>
#include <LeafSegment.hpp>
#include <sorghum_factory_export.h>
using namespace UniEngine;
namespace SorghumFactory {
struct SORGHUM_FACTORY_API SplineNode {
  glm::vec3 m_position;
  float m_theta;
  float m_width;
  glm::vec3 m_axis;
  bool m_isLeaf;
  float m_surfacePush = 0.0f;
  SplineNode(glm::vec3 position, float angle, float width, glm::vec3 axis,
            bool isLeaf, float surfacePush);
  SplineNode();
};
enum class SORGHUM_FACTORY_API SplineType{
  BezierCurve,
  Procedural
};
class SORGHUM_FACTORY_API Spline : public IPrivateComponent {
public:
  SplineType m_type = SplineType::BezierCurve;
  //The "normal" direction of the leaf.
  glm::vec3 m_left;

  float m_startingPoint = -1;

  float m_wavinessPeriod = 1.25f;
  float m_waviness = 0.5f;

  //Spline representation from procedural plant.
  int m_order = 0;
  float m_unitLength = 0.4f;
  int m_unitAmount = 16;
  float m_gravitropism = 2;
  float m_gravitropismFactor = 0.5;
  glm::vec3 m_initialDirection = glm::vec3(0, 1, 0);

  float m_stemWidthMax = 0.06f;
  UniEngine::Curve m_stemWidthDistribution;

  float m_leafMaxWidth = 0.2f;
  float m_leafWidthDecreaseStart = 0.5;
  //Spline representation from Mathieu's skeleton

  std::vector<BezierCurve> m_curves;

  //Geometry generation
  int m_segmentAmount = 2;
  int m_step = 2;
  std::vector<SplineNode> m_nodes;
  std::vector<LeafSegment> m_segments;
  std::vector<Vertex> m_vertices;
  std::vector<unsigned> m_indices;
  glm::vec4 m_vertexColor = glm::vec4(0, 1, 0, 1);
  //Import from Mathieu's procedural skeleton
  void Import(std::ifstream &stream);
  glm::vec3 EvaluatePoint(float point);
  glm::vec3 EvaluateAxis(float point);

  void OnInspect() override;
  void Serialize(YAML::Emitter &out) override;
  void Deserialize(const YAML::Node &in) override;
  void Copy(const std::shared_ptr<Spline> &target);
  int FormNodes(const std::shared_ptr<Spline>& stemSpline);
  void GenerateGeometry(const std::shared_ptr<Spline>& stemSpline);
};

} // namespace SorghumFactory