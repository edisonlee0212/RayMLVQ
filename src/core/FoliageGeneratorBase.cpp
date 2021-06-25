#include <FoliageGeneratorBase.hpp>
#include <PlantManager.hpp>
using namespace PlantFactory;
std::shared_ptr<Texture2D> DefaultFoliageGenerator::m_leafSurfaceTex = nullptr;


void DefaultFoliageGenerator::GenerateLeaves(Entity& internode, glm::mat4& treeTransform,
                                                           std::vector<glm::mat4>& leafTransforms, bool isLeft)
{
}

DefaultFoliageGenerator::DefaultFoliageGenerator()
{
	m_defaultFoliageInfo = DefaultFoliageInfo();
	m_archetype = EntityManager::CreateEntityArchetype("Pine Foliage", DefaultFoliageInfo());

	m_leafMaterial = ResourceManager::CreateResource<Material>();
	m_leafMaterial->SetProgram(DefaultResources::GLPrograms::StandardInstancedProgram);
	m_leafMaterial->m_alphaDiscardEnabled = true;
	m_leafMaterial->m_alphaDiscardOffset = 0.1f;
	m_leafMaterial->m_cullingMode = MaterialCullingMode::Off;
	if (!m_leafSurfaceTex) m_leafSurfaceTex = ResourceManager::LoadTexture(false, FileIO::GetAssetFolderPath() + "Textures/Leaf/Pine/level0.png");
	//_LeafMaterial->SetTexture(_LeafSurfaceTex);
	m_leafMaterial->m_albedoColor = glm::normalize(glm::vec3(60.0f / 256.0f, 140.0f / 256.0f, 0.0f));
	m_leafMaterial->m_metallic = 0.0f;
	m_leafMaterial->m_roughness = 0.3f;
	m_leafMaterial->m_ambientOcclusion = glm::linearRand(0.4f, 0.8f);
}

void DefaultFoliageGenerator::Generate()
{
	const auto tree = GetOwner();
	auto treeTransform = EntityManager::GetComponentData<GlobalTransform>(tree);
	Entity foliageEntity;
	bool found = false;
	EntityManager::ForEachChild(tree, [&found, &foliageEntity](Entity child)
		{
			if (child.HasComponentData<DefaultFoliageInfo>())
			{
				found = true;
				foliageEntity = child;
			}
		}
	);
	if (!found)
	{
		foliageEntity = EntityManager::CreateEntity(m_archetype, "Foliage");
		EntityManager::SetParent(foliageEntity, tree);
		auto particleSys = std::make_unique<Particles>();
		particleSys->m_material = m_leafMaterial;
		particleSys->m_mesh = DefaultResources::Primitives::Quad;
		particleSys->m_forwardRendering = false;
		Transform transform;
		transform.m_value = glm::translate(glm::vec3(0.0f)) * glm::scale(glm::vec3(1.0f));
		foliageEntity.SetPrivateComponent(std::move(particleSys));
		foliageEntity.SetComponentData(transform);
		foliageEntity.SetComponentData(m_defaultFoliageInfo);
	}
	auto& particleSys = foliageEntity.GetPrivateComponent<Particles>();
	particleSys->m_matrices.clear();
	GenerateLeaves(EntityManager::GetChildren(tree)[0], treeTransform.m_value, particleSys->m_matrices, true);
}

void DefaultFoliageGenerator::OnGui()
{
	if (ImGui::Button("Regenerate")) Generate();
	ImGui::DragFloat2("Leaf Size XY", static_cast<float*>(static_cast<void*>(&m_defaultFoliageInfo.m_leafSize)), 0.01f);
	ImGui::DragFloat("LeafIlluminationLimit", &m_defaultFoliageInfo.m_leafIlluminationLimit, 0.01f);
	ImGui::DragFloat("LeafInhibitorFactor", &m_defaultFoliageInfo.m_leafInhibitorFactor, 0.01f);
	ImGui::Checkbox("IsBothSide", &m_defaultFoliageInfo.m_isBothSide);
	ImGui::DragInt("SideLeafAmount", &m_defaultFoliageInfo.m_sideLeafAmount, 0.01f);
	ImGui::DragFloat("StartBendingAngle", &m_defaultFoliageInfo.m_startBendingAngle, 0.01f);
	ImGui::DragFloat("BendingAngleIncrement", &m_defaultFoliageInfo.m_bendingAngleIncrement, 0.01f);
	ImGui::DragFloat("LeafPhotoTropism", &m_defaultFoliageInfo.m_leafPhotoTropism, 0.01f);
	ImGui::DragFloat("LeafGravitropism", &m_defaultFoliageInfo.m_leafGravitropism, 0.01f);
	ImGui::DragFloat("LeafDistance", &m_defaultFoliageInfo.m_leafDistance, 0.01f);
}
