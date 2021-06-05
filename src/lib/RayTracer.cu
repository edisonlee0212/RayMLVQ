#include <RayTracer.hpp>
#include <optix_function_table_definition.h>
#include <FileUtil.hpp>

#include <glm/gtx/transform.hpp>
#define GL_TEXTURE_CUBE_MAP 0x8513
#include <cuda_gl_interop.h>
#include <RayDataDefinations.hpp>

using namespace RayMLVQ;

void RayTracer::SetStatusChanged(const bool& value)
{
	m_statusChanged = value;
}

bool RayTracer::RenderDefault(const DefaultRenderingProperties& properties, std::vector<TriangleMesh>& meshes)
{
	if (properties.m_frameSize.x == 0 | properties.m_frameSize.y == 0) return true;
	if (!m_hasAccelerationStructure) return false;
	std::vector<std::pair<unsigned, cudaTextureObject_t>> boundTextures;
	std::vector<cudaGraphicsResource_t> boundResources;
	BuildShaderBindingTable(meshes, boundTextures, boundResources);
	if (m_defaultRenderingLaunchParams.m_defaultRenderingProperties.Changed(properties)) {
		m_defaultRenderingLaunchParams.m_defaultRenderingProperties = properties;
		m_statusChanged = true;
	}
	if (!m_accumulate || m_statusChanged) {
		m_defaultRenderingLaunchParams.m_frame.m_frameId = 0;
		m_statusChanged = false;
	}
#pragma region Bind texture
	cudaArray_t outputArray;
	cudaGraphicsResource_t outputTexture;
	cudaArray_t environmentalMapPosXArray;
	cudaArray_t environmentalMapNegXArray;
	cudaArray_t environmentalMapPosYArray;
	cudaArray_t environmentalMapNegYArray;
	cudaArray_t environmentalMapPosZArray;
	cudaArray_t environmentalMapNegZArray;
	cudaGraphicsResource_t environmentalMapTexture;
#pragma region Bind output texture as cudaSurface
	CUDA_CHECK(GraphicsGLRegisterImage(&outputTexture, m_defaultRenderingLaunchParams.m_defaultRenderingProperties.m_outputTextureId, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsNone));
	CUDA_CHECK(GraphicsMapResources(1, &outputTexture, nullptr));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&outputArray, outputTexture, 0, 0));
	// Specify surface
	struct cudaResourceDesc cudaResourceDesc;
	memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
	cudaResourceDesc.resType = cudaResourceTypeArray;
	// Create the surface objects
	cudaResourceDesc.res.array.array = outputArray;
	// Create surface object
	CUDA_CHECK(CreateSurfaceObject(&m_defaultRenderingLaunchParams.m_frame.m_outputTexture, &cudaResourceDesc));
#pragma endregion
#pragma region Bind environmental map as cudaTexture
	CUDA_CHECK(GraphicsGLRegisterImage(&environmentalMapTexture, m_defaultRenderingLaunchParams.m_defaultRenderingProperties.m_environmentalMapId, GL_TEXTURE_CUBE_MAP, cudaGraphicsRegisterFlagsNone));
	CUDA_CHECK(GraphicsMapResources(1, &environmentalMapTexture, nullptr));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosXArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveX, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegXArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeX, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosYArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveY, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegYArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeY, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosZArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveZ, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegZArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeZ, 0));
	memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
	cudaResourceDesc.resType = cudaResourceTypeArray;
	struct cudaTextureDesc cudaTextureDesc;
	memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
	cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
	cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
	cudaTextureDesc.filterMode = cudaFilterModeLinear;
	cudaTextureDesc.readMode = cudaReadModeElementType;
	cudaTextureDesc.normalizedCoords = 1;
	// Create texture object
	cudaResourceDesc.res.array.array = environmentalMapPosXArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[0], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegXArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[1], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapPosYArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[2], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegYArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[3], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapPosZArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[4], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegZArray;
	CUDA_CHECK(CreateTextureObject(&m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[5], &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
#pragma endregion
#pragma region Upload parameters
	m_defaultRenderingLaunchParamsBuffer.Upload(&m_defaultRenderingLaunchParams, 1);
	m_defaultRenderingLaunchParams.m_frame.m_frameId++;
#pragma endregion
#pragma endregion
#pragma region Launch rays from camera
	OPTIX_CHECK(optixLaunch(/*! pipeline we're launching launch: */
		m_defaultRenderingPipeline.m_pipeline, m_stream,
		/*! parameters and SBT */
		m_defaultRenderingLaunchParamsBuffer.DevicePointer(),
		m_defaultRenderingLaunchParamsBuffer.m_sizeInBytes,
		&m_defaultRenderingPipeline.m_sbt,
		/*! dimensions of the launch: */
		m_defaultRenderingLaunchParams.m_defaultRenderingProperties.m_frameSize.x,
		m_defaultRenderingLaunchParams.m_defaultRenderingProperties.m_frameSize.y,
		1
	));
#pragma endregion
	CUDA_SYNC_CHECK();
#pragma region Remove texture binding.
	CUDA_CHECK(DestroySurfaceObject(m_defaultRenderingLaunchParams.m_frame.m_outputTexture));
	m_defaultRenderingLaunchParams.m_frame.m_outputTexture = 0;
	CUDA_CHECK(GraphicsUnmapResources(1, &outputTexture, 0));
	CUDA_CHECK(GraphicsUnregisterResource(outputTexture));

	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[0]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[0] = 0;
	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[1]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[1] = 0;
	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[2]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[2] = 0;
	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[3]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[3] = 0;
	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[4]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[4] = 0;
	CUDA_CHECK(DestroyTextureObject(m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[5]));
	m_defaultRenderingLaunchParams.m_skylight.m_environmentalMaps[5] = 0;

	CUDA_CHECK(GraphicsUnmapResources(1, &environmentalMapTexture, 0));
	CUDA_CHECK(GraphicsUnregisterResource(environmentalMapTexture));
#pragma endregion

	for (int i = 0; i < boundResources.size(); i++)
	{
		CUDA_CHECK(DestroySurfaceObject(boundTextures[i].second));
		CUDA_CHECK(GraphicsUnmapResources(1, &boundResources[i], 0));
		CUDA_CHECK(GraphicsUnregisterResource(boundResources[i]));
	}
	return true;
}

bool RayTracer::RenderRayMLVQ(const RayMLVQRenderingProperties& properties, std::vector<TriangleMesh>& meshes)
{
	if (properties.m_frameSize.x == 0 | properties.m_frameSize.y == 0) return true;
	if (!m_hasAccelerationStructure) return false;
	std::vector<std::pair<unsigned, cudaTextureObject_t>> boundTextures;
	std::vector<cudaGraphicsResource_t> boundResources;
	BuildShaderBindingTable(meshes, boundTextures, boundResources);
	if (m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties.Changed(properties)) {
		m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties = properties;
		m_statusChanged = true;
	}
	if (!m_accumulate || m_statusChanged) {
		m_rayMLVQRenderingLaunchParams.m_frame.m_frameId = 0;
		m_statusChanged = false;
	}
#pragma region Bind texture
	cudaArray_t outputArray;
	cudaGraphicsResource_t outputTexture;
	cudaArray_t environmentalMapPosXArray;
	cudaArray_t environmentalMapNegXArray;
	cudaArray_t environmentalMapPosYArray;
	cudaArray_t environmentalMapNegYArray;
	cudaArray_t environmentalMapPosZArray;
	cudaArray_t environmentalMapNegZArray;
	cudaGraphicsResource_t environmentalMapTexture;
#pragma region Bind output texture as cudaSurface
	CUDA_CHECK(GraphicsGLRegisterImage(&outputTexture, m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties.m_outputTextureId, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsNone));
	CUDA_CHECK(GraphicsMapResources(1, &outputTexture, nullptr));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&outputArray, outputTexture, 0, 0));
	// Specify surface
	struct cudaResourceDesc cudaResourceDesc;
	memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
	cudaResourceDesc.resType = cudaResourceTypeArray;
	// Create the surface objects
	cudaResourceDesc.res.array.array = outputArray;
	// Create surface object
	CUDA_CHECK(CreateSurfaceObject(&m_rayMLVQRenderingLaunchParams.m_frame.m_outputTexture, &cudaResourceDesc));
#pragma endregion
#pragma region Bind environmental map as cudaTexture
	CUDA_CHECK(GraphicsGLRegisterImage(&environmentalMapTexture, m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties.m_environmentalMapId, GL_TEXTURE_CUBE_MAP, cudaGraphicsRegisterFlagsNone));
	CUDA_CHECK(GraphicsMapResources(1, &environmentalMapTexture, nullptr));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosXArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveX, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegXArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeX, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosYArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveY, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegYArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeY, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapPosZArray, environmentalMapTexture, cudaGraphicsCubeFacePositiveZ, 0));
	CUDA_CHECK(GraphicsSubResourceGetMappedArray(&environmentalMapNegZArray, environmentalMapTexture, cudaGraphicsCubeFaceNegativeZ, 0));
	memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
	cudaResourceDesc.resType = cudaResourceTypeArray;
	struct cudaTextureDesc cudaTextureDesc;
	memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
	cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
	cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
	cudaTextureDesc.filterMode = cudaFilterModeLinear;
	cudaTextureDesc.readMode = cudaReadModeElementType;
	cudaTextureDesc.normalizedCoords = 1;
	// Create texture object
	cudaResourceDesc.res.array.array = environmentalMapPosXArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[0], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegXArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[1], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapPosYArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[2], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegYArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[3], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapPosZArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[4], &cudaResourceDesc, &cudaTextureDesc, nullptr));
	cudaResourceDesc.res.array.array = environmentalMapNegZArray;
	CUDA_CHECK(CreateTextureObject(&m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[5], &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
#pragma endregion
#pragma region Upload parameters
	m_rayMLVQRenderingLaunchParamsBuffer.Upload(&m_rayMLVQRenderingLaunchParams, 1);
	m_rayMLVQRenderingLaunchParams.m_frame.m_frameId++;
#pragma endregion
#pragma endregion
#pragma region Launch rays from camera
	OPTIX_CHECK(optixLaunch(/*! pipeline we're launching launch: */
		m_rayMLVQRenderingPipeline.m_pipeline, m_stream,
		/*! parameters and SBT */
		m_rayMLVQRenderingLaunchParamsBuffer.DevicePointer(),
		m_rayMLVQRenderingLaunchParamsBuffer.m_sizeInBytes,
		&m_rayMLVQRenderingPipeline.m_sbt,
		/*! dimensions of the launch: */
		m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties.m_frameSize.x,
		m_rayMLVQRenderingLaunchParams.m_rayMLVQRenderingProperties.m_frameSize.y,
		1
	));
#pragma endregion
	CUDA_SYNC_CHECK();
#pragma region Remove texture binding.
	CUDA_CHECK(DestroySurfaceObject(m_rayMLVQRenderingLaunchParams.m_frame.m_outputTexture));
	m_rayMLVQRenderingLaunchParams.m_frame.m_outputTexture = 0;
	CUDA_CHECK(GraphicsUnmapResources(1, &outputTexture, 0));
	CUDA_CHECK(GraphicsUnregisterResource(outputTexture));

	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[0]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[0] = 0;
	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[1]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[1] = 0;
	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[2]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[2] = 0;
	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[3]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[3] = 0;
	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[4]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[4] = 0;
	CUDA_CHECK(DestroyTextureObject(m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[5]));
	m_rayMLVQRenderingLaunchParams.m_skylight.m_environmentalMaps[5] = 0;

	CUDA_CHECK(GraphicsUnmapResources(1, &environmentalMapTexture, 0));
	CUDA_CHECK(GraphicsUnregisterResource(environmentalMapTexture));
#pragma endregion

	for (int i = 0; i < boundResources.size(); i++)
	{
		CUDA_CHECK(DestroySurfaceObject(boundTextures[i].second));
		CUDA_CHECK(GraphicsUnmapResources(1, &boundResources[i], 0));
		CUDA_CHECK(GraphicsUnregisterResource(boundResources[i]));
	}
	return true;
}

void RayTracer::EstimateIllumination(const size_t& size, const IlluminationEstimationProperties& properties, CudaBuffer& lightProbes, std::vector<TriangleMesh>& meshes)
{
	if (!m_hasAccelerationStructure) return;
	std::vector<std::pair<unsigned, cudaTextureObject_t>> boundTextures;
	std::vector<cudaGraphicsResource_t> boundResources;
	BuildShaderBindingTable(meshes, boundTextures, boundResources);

#pragma region Upload parameters
	m_defaultIlluminationEstimationLaunchParams.m_size = size;
	m_defaultIlluminationEstimationLaunchParams.m_defaultIlluminationEstimationProperties = properties;
	m_defaultIlluminationEstimationLaunchParams.m_lightProbes = reinterpret_cast<LightProbe<float>*>(lightProbes.DevicePointer());
	m_defaultIlluminationEstimationLaunchParamsBuffer.Upload(&m_defaultIlluminationEstimationLaunchParams, 1);
#pragma endregion
#pragma endregion
	if (size == 0)
	{
		std::cout << "Error!" << std::endl;
		return;
	}
#pragma region Launch rays from camera
	OPTIX_CHECK(optixLaunch(/*! pipeline we're launching launch: */
		m_defaultIlluminationEstimationPipeline.m_pipeline, m_stream,
		/*! parameters and SBT */
		m_defaultIlluminationEstimationLaunchParamsBuffer.DevicePointer(),
		m_defaultIlluminationEstimationLaunchParamsBuffer.m_sizeInBytes,
		&m_defaultIlluminationEstimationPipeline.m_sbt,
		/*! dimensions of the launch: */
		size,
		1,
		1
	));
#pragma endregion
	CUDA_SYNC_CHECK();
	for (int i = 0; i < boundResources.size(); i++)
	{
		CUDA_CHECK(DestroySurfaceObject(boundTextures[i].second));
		CUDA_CHECK(GraphicsUnmapResources(1, &boundResources[i], 0));
		CUDA_CHECK(GraphicsUnregisterResource(boundResources[i]));
	}
}

RayTracer::RayTracer()
{
	m_defaultRenderingLaunchParams.m_frame.m_frameId = 0;
	//std::cout << "#Optix: creating optix context ..." << std::endl;
	CreateContext();
	//std::cout << "#Optix: setting up module ..." << std::endl;
	CreateModules();
	//std::cout << "#Optix: creating raygen programs ..." << std::endl;
	CreateRayGenPrograms();
	//std::cout << "#Optix: creating miss programs ..." << std::endl;
	CreateMissPrograms();
	//std::cout << "#Optix: creating hitgroup programs ..." << std::endl;
	CreateHitGroupPrograms();
	//std::cout << "#Optix: setting up optix pipeline ..." << std::endl;
	AssemblePipelines();

	m_defaultRenderingLaunchParamsBuffer.Resize(sizeof(m_defaultRenderingLaunchParams));
	std::cout << "#Optix: context, module, pipeline, etc, all set up ..." << std::endl;
}

void RayTracer::SetSkylightSize(const float& value)
{
	m_defaultRenderingLaunchParams.m_skylight.m_lightSize = value;
	m_statusChanged = true;
}

void RayTracer::SetSkylightDir(const glm::vec3& value)
{
	m_defaultRenderingLaunchParams.m_skylight.m_direction = value;
	m_statusChanged = true;
}

static void context_log_cb(const unsigned int level,
	const char* tag,
	const char* message,
	void*)
{
	fprintf(stderr, "[%2d][%12s]: %s\n", static_cast<int>(level), tag, message);
}

void RayTracer::CreateContext()
{
	// for this sample, do everything on one device
	const int deviceID = 0;
	CUDA_CHECK(StreamCreate(&m_stream));
	CUDA_CHECK(GetDeviceProperties(&m_deviceProps, deviceID));
	std::cout << "#Optix: running on device: " << m_deviceProps.name << std::endl;
	const CUresult cuRes = cuCtxGetCurrent(&m_cudaContext);
	if (cuRes != CUDA_SUCCESS)
		fprintf(stderr, "Error querying current context: error code %d\n", cuRes);
	OPTIX_CHECK(optixDeviceContextCreate(m_cudaContext, nullptr, &m_optixContext));
	OPTIX_CHECK(optixDeviceContextSetLogCallback
	(m_optixContext, context_log_cb, nullptr, 4));
}

extern "C" char DEFAULT_RENDERING_PTX[];
extern "C" char ILLUMINATION_ESTIMATION_PTX[];

extern "C" char RAYMLVQ_RENDERING_PTX[];

void RayTracer::CreateModules()
{
	CreateModule(m_defaultRenderingPipeline, DEFAULT_RENDERING_PTX, "defaultRenderingLaunchParams");
	CreateModule(m_defaultIlluminationEstimationPipeline, ILLUMINATION_ESTIMATION_PTX, "defaultIlluminationEstimationLaunchParams");
	CreateModule(m_rayMLVQRenderingPipeline, RAYMLVQ_RENDERING_PTX, "rayMLVQRenderingLaunchParams");
}

void RayTracer::CreateRayGenPrograms()
{
	CreateRayGenProgram(m_defaultRenderingPipeline, "__raygen__renderFrame");
	CreateRayGenProgram(m_defaultIlluminationEstimationPipeline, "__raygen__illuminationEstimation");
	CreateRayGenProgram(m_rayMLVQRenderingPipeline, "__raygen__renderFrame");
}

void RayTracer::CreateMissPrograms()
{
	{
		m_defaultRenderingPipeline.m_missProgramGroups.resize(static_cast<int>(DefaultRenderingRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_MISS;
		pgDesc.miss.module = m_defaultRenderingPipeline.m_module;

		// ------------------------------------------------------------------
		// radiance rays
		// ------------------------------------------------------------------
		pgDesc.miss.entryFunctionName = "__miss__radiance";

		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultRenderingPipeline.m_missProgramGroups[static_cast<int>(DefaultRenderingRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
		// ------------------------------------------------------------------
		// shadow rays
		// ------------------------------------------------------------------
		pgDesc.miss.entryFunctionName = "__miss__shadow";
		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultRenderingPipeline.m_missProgramGroups[static_cast<int>(DefaultRenderingRayType::ShadowRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
	{
		m_defaultIlluminationEstimationPipeline.m_missProgramGroups.resize(static_cast<int>(DefaultIlluminationEstimationRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_MISS;
		pgDesc.miss.module = m_defaultIlluminationEstimationPipeline.m_module;

		// ------------------------------------------------------------------
		// radiance rays
		// ------------------------------------------------------------------
		pgDesc.miss.entryFunctionName = "__miss__illuminationEstimation";

		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultIlluminationEstimationPipeline.m_missProgramGroups[static_cast<int>(DefaultIlluminationEstimationRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
	{
		m_rayMLVQRenderingPipeline.m_missProgramGroups.resize(static_cast<int>(RayMLVQRenderingRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_MISS;
		pgDesc.miss.module = m_rayMLVQRenderingPipeline.m_module;

		// ------------------------------------------------------------------
		// radiance rays
		// ------------------------------------------------------------------
		pgDesc.miss.entryFunctionName = "__miss__radiance";

		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_rayMLVQRenderingPipeline.m_missProgramGroups[static_cast<int>(RayMLVQRenderingRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
}

void RayTracer::CreateHitGroupPrograms()
{
	{
		m_defaultRenderingPipeline.m_hitGroupProgramGroups.resize(static_cast<int>(DefaultRenderingRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_HITGROUP;
		pgDesc.hitgroup.moduleCH = m_defaultRenderingPipeline.m_module;
		pgDesc.hitgroup.moduleAH = m_defaultRenderingPipeline.m_module;
		// -------------------------------------------------------
		// radiance rays
		// -------------------------------------------------------
		pgDesc.hitgroup.entryFunctionNameCH = "__closesthit__radiance";
		pgDesc.hitgroup.entryFunctionNameAH = "__anyhit__radiance";
		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultRenderingPipeline.m_hitGroupProgramGroups[static_cast<int>(DefaultRenderingRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;

		// -------------------------------------------------------
		// shadow rays: technically we don't need this hit group,
		// since we just use the miss shader to check if we were not
		// in shadow
		// -------------------------------------------------------
		pgDesc.hitgroup.entryFunctionNameCH = "__closesthit__shadow";
		pgDesc.hitgroup.entryFunctionNameAH = "__anyhit__shadow";

		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultRenderingPipeline.m_hitGroupProgramGroups[static_cast<int>(DefaultRenderingRayType::ShadowRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
	{
		m_defaultIlluminationEstimationPipeline.m_hitGroupProgramGroups.resize(static_cast<int>(DefaultIlluminationEstimationRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_HITGROUP;
		pgDesc.hitgroup.moduleCH = m_defaultIlluminationEstimationPipeline.m_module;
		pgDesc.hitgroup.moduleAH = m_defaultIlluminationEstimationPipeline.m_module;
		// -------------------------------------------------------
		// radiance rays
		// -------------------------------------------------------
		pgDesc.hitgroup.entryFunctionNameCH = "__closesthit__illuminationEstimation";
		pgDesc.hitgroup.entryFunctionNameAH = "__anyhit__illuminationEstimation";
		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_defaultIlluminationEstimationPipeline.m_hitGroupProgramGroups[static_cast<int>(DefaultIlluminationEstimationRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
	{
		m_rayMLVQRenderingPipeline.m_hitGroupProgramGroups.resize(static_cast<int>(RayMLVQRenderingRayType::RayTypeCount));
		char log[2048];
		size_t sizeofLog = sizeof(log);

		OptixProgramGroupOptions pgOptions = {};
		OptixProgramGroupDesc pgDesc = {};
		pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_HITGROUP;
		pgDesc.hitgroup.moduleCH = m_rayMLVQRenderingPipeline.m_module;
		pgDesc.hitgroup.moduleAH = m_rayMLVQRenderingPipeline.m_module;
		// -------------------------------------------------------
		// radiance rays
		// -------------------------------------------------------
		pgDesc.hitgroup.entryFunctionNameCH = "__closesthit__radiance";
		pgDesc.hitgroup.entryFunctionNameAH = "__anyhit__radiance";
		OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
			&pgDesc,
			1,
			&pgOptions,
			log, &sizeofLog,
			&m_rayMLVQRenderingPipeline.m_hitGroupProgramGroups[static_cast<int>(RayMLVQRenderingRayType::RadianceRayType)]
		));
		if (sizeofLog > 1) std::cout << log << std::endl;
	}
}

__global__ void ApplyTransformKernel(
	int size, glm::mat4 globalTransform,
	glm::vec3* positions, glm::vec3* normals, glm::vec3* tangents,
	glm::vec3* targetPositions, glm::vec3* targetNormals, glm::vec3* targetTangents)
{
	const int idx = threadIdx.x + blockIdx.x * blockDim.x;
	if (idx < size)
	{
		targetPositions[idx] = globalTransform * glm::vec4(positions[idx], 1.0f);
		targetNormals[idx] = glm::normalize(globalTransform * glm::vec4(normals[idx], 0.0f));
		targetTangents[idx] = glm::normalize(globalTransform * glm::vec4(tangents[idx], 0.0f));
	}
}

void RayTracer::BuildAccelerationStructure(std::vector<TriangleMesh>& meshes)
{
	bool uploadVertices = false;
	if (m_positionsBuffer.size() != meshes.size()) uploadVertices = true;
	else {
		for (auto& i : meshes)
		{
			if (i.m_verticesUpdateFlag) {
				uploadVertices = true;
				break;
			}
		}
	}
	if (uploadVertices) {
		for (auto& i : m_positionsBuffer) i.Free();
		for (auto& i : m_trianglesBuffer) i.Free();
		for (auto& i : m_normalsBuffer) i.Free();
		for (auto& i : m_tangentsBuffer) i.Free();
		for (auto& i : m_colorsBuffer) i.Free();
		for (auto& i : m_texCoordsBuffer) i.Free();
		for (auto& i : m_transformedPositionsBuffer) i.Free();
		for (auto& i : m_transformedNormalsBuffer) i.Free();
		for (auto& i : m_transformedTangentsBuffer) i.Free();

		m_positionsBuffer.clear();
		m_trianglesBuffer.clear();
		m_normalsBuffer.clear();
		m_tangentsBuffer.clear();
		m_colorsBuffer.clear();
		m_texCoordsBuffer.clear();
		m_transformedPositionsBuffer.clear();
		m_transformedNormalsBuffer.clear();
		m_transformedTangentsBuffer.clear();

		m_positionsBuffer.resize(meshes.size());
		m_trianglesBuffer.resize(meshes.size());
		m_normalsBuffer.resize(meshes.size());
		m_tangentsBuffer.resize(meshes.size());
		m_colorsBuffer.resize(meshes.size());
		m_texCoordsBuffer.resize(meshes.size());
		m_transformedTangentsBuffer.resize(meshes.size());
		m_transformedNormalsBuffer.resize(meshes.size());
		m_transformedPositionsBuffer.resize(meshes.size());
	}
	OptixTraversableHandle asHandle = 0;

	// ==================================================================
	// triangle inputs
	// ==================================================================
	std::vector<OptixBuildInput> triangleInput(meshes.size());
	std::vector<CUdeviceptr> deviceVertexPositions(meshes.size());
	std::vector<CUdeviceptr> deviceVertexTriangles(meshes.size());
	std::vector<CUdeviceptr> deviceTransforms(meshes.size());
	std::vector<uint32_t> triangleInputFlags(meshes.size());

	for (int meshID = 0; meshID < meshes.size(); meshID++) {
		// upload the model to the device: the builder
		TriangleMesh& triangleMesh = meshes[meshID];
		if (uploadVertices)
		{
			m_positionsBuffer[meshID].Upload(*triangleMesh.m_positions);
			m_tangentsBuffer[meshID].Upload(*triangleMesh.m_tangents);
			m_normalsBuffer[meshID].Upload(*triangleMesh.m_normals);
			m_transformedPositionsBuffer[meshID].Resize(triangleMesh.m_positions->size() * sizeof(glm::vec3));
			m_transformedNormalsBuffer[meshID].Resize(triangleMesh.m_normals->size() * sizeof(glm::vec3));
			m_transformedTangentsBuffer[meshID].Resize(triangleMesh.m_tangents->size() * sizeof(glm::vec3));
		}

		if (uploadVertices || triangleMesh.m_transformUpdateFlag) {
			int blockSize = 0;      // The launch configurator returned block size 
			int minGridSize = 0;    // The minimum grid size needed to achieve the maximum occupancy for a full device launch 
			int gridSize = 0;       // The actual grid size needed, based on input size
			int size = triangleMesh.m_positions->size();
			cudaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, ApplyTransformKernel, 0, size);
			gridSize = (size + blockSize - 1) / blockSize;
			ApplyTransformKernel << <gridSize, blockSize >> > (size, triangleMesh.m_globalTransform,
				static_cast<glm::vec3*>(m_positionsBuffer[meshID].m_dPtr), static_cast<glm::vec3*>(m_normalsBuffer[meshID].m_dPtr), static_cast<glm::vec3*>(m_tangentsBuffer[meshID].m_dPtr),
				static_cast<glm::vec3*>(m_transformedPositionsBuffer[meshID].m_dPtr), static_cast<glm::vec3*>(m_transformedNormalsBuffer[meshID].m_dPtr), static_cast<glm::vec3*>(m_transformedTangentsBuffer[meshID].m_dPtr));
			CUDA_SYNC_CHECK();
		}

		triangleMesh.m_verticesUpdateFlag = false;
		triangleMesh.m_transformUpdateFlag = false;

		m_texCoordsBuffer[meshID].Upload(*triangleMesh.m_texCoords);
		m_colorsBuffer[meshID].Upload(*triangleMesh.m_colors);
		m_trianglesBuffer[meshID].Upload(*triangleMesh.m_triangles);
		triangleInput[meshID] = {};
		triangleInput[meshID].type
			= OPTIX_BUILD_INPUT_TYPE_TRIANGLES;

		// create local variables, because we need a *pointer* to the
		// device pointers
		deviceVertexPositions[meshID] = m_transformedPositionsBuffer[meshID].DevicePointer();
		deviceVertexTriangles[meshID] = m_trianglesBuffer[meshID].DevicePointer();

		triangleInput[meshID].triangleArray.vertexFormat = OPTIX_VERTEX_FORMAT_FLOAT3;
		triangleInput[meshID].triangleArray.vertexStrideInBytes = sizeof(glm::vec3);
		triangleInput[meshID].triangleArray.numVertices = static_cast<int>(triangleMesh.m_positions->size());
		triangleInput[meshID].triangleArray.vertexBuffers = &deviceVertexPositions[meshID];

		//triangleInput[meshID].triangleArray.transformFormat = OPTIX_TRANSFORM_FORMAT_MATRIX_FLOAT12;
		//triangleInput[meshID].triangleArray.preTransform = deviceTransforms[meshID];

		triangleInput[meshID].triangleArray.indexFormat = OPTIX_INDICES_FORMAT_UNSIGNED_INT3;
		triangleInput[meshID].triangleArray.indexStrideInBytes = sizeof(glm::uvec3);
		triangleInput[meshID].triangleArray.numIndexTriplets = static_cast<int>(triangleMesh.m_triangles->size());
		triangleInput[meshID].triangleArray.indexBuffer = deviceVertexTriangles[meshID];

		triangleInputFlags[meshID] = 0;

		// in this example we have one SBT entry, and no per-primitive
		// materials:
		triangleInput[meshID].triangleArray.flags = &triangleInputFlags[meshID];
		triangleInput[meshID].triangleArray.numSbtRecords = 1;
		triangleInput[meshID].triangleArray.sbtIndexOffsetBuffer = 0;
		triangleInput[meshID].triangleArray.sbtIndexOffsetSizeInBytes = 0;
		triangleInput[meshID].triangleArray.sbtIndexOffsetStrideInBytes = 0;
	}
	// ==================================================================
	// BLAS setup
	// ==================================================================

	OptixAccelBuildOptions accelerateOptions = {};
	accelerateOptions.buildFlags = OPTIX_BUILD_FLAG_NONE
		| OPTIX_BUILD_FLAG_ALLOW_COMPACTION
		;
	accelerateOptions.motionOptions.numKeys = 1;
	accelerateOptions.operation = OPTIX_BUILD_OPERATION_BUILD;

	OptixAccelBufferSizes blasBufferSizes;
	OPTIX_CHECK(optixAccelComputeMemoryUsage
	(m_optixContext,
		&accelerateOptions,
		triangleInput.data(),
		static_cast<int>(meshes.size()),  // num_build_inputs
		&blasBufferSizes
	));

	// ==================================================================
	// prepare compaction
	// ==================================================================

	CudaBuffer compactedSizeBuffer;
	compactedSizeBuffer.Resize(sizeof(uint64_t));

	OptixAccelEmitDesc emitDesc;
	emitDesc.type = OPTIX_PROPERTY_TYPE_COMPACTED_SIZE;
	emitDesc.result = compactedSizeBuffer.DevicePointer();

	// ==================================================================
	// execute build (main stage)
	// ==================================================================

	CudaBuffer tempBuffer;
	tempBuffer.Resize(blasBufferSizes.tempSizeInBytes);

	CudaBuffer outputBuffer;
	outputBuffer.Resize(blasBufferSizes.outputSizeInBytes);

	OPTIX_CHECK(optixAccelBuild(m_optixContext,
		/* stream */nullptr,
		&accelerateOptions,
		triangleInput.data(),
		static_cast<int>(meshes.size()),
		tempBuffer.DevicePointer(),
		tempBuffer.m_sizeInBytes,

		outputBuffer.DevicePointer(),
		outputBuffer.m_sizeInBytes,

		&asHandle,

		&emitDesc, 1
	));
	CUDA_SYNC_CHECK();

	// ==================================================================
	// perform compaction
	// ==================================================================
	uint64_t compactedSize;
	compactedSizeBuffer.Download(&compactedSize, 1);

	m_acceleratedStructuresBuffer.Resize(compactedSize);
	OPTIX_CHECK(optixAccelCompact(m_optixContext,
		/*stream:*/nullptr,
		asHandle,
		m_acceleratedStructuresBuffer.DevicePointer(),
		m_acceleratedStructuresBuffer.m_sizeInBytes,
		&asHandle));
	CUDA_SYNC_CHECK();

	// ==================================================================
	// aaaaaand .... clean up
	// ==================================================================
	outputBuffer.Free(); // << the Uncompacted, temporary output buffer
	tempBuffer.Free();
	compactedSizeBuffer.Free();

	m_defaultRenderingLaunchParams.m_traversable = asHandle;
	m_defaultRenderingLaunchParams.m_traversable = asHandle;
	m_hasAccelerationStructure = true;
}

void RayTracer::SetAccumulate(const bool& value)
{
	m_accumulate = value;
	m_statusChanged = true;
}

void RayTracer::AssemblePipelines()
{
	AssemblePipeline(m_defaultRenderingPipeline);
	AssemblePipeline(m_defaultIlluminationEstimationPipeline);
	AssemblePipeline(m_rayMLVQRenderingPipeline);
}

void RayTracer::CreateRayGenProgram(RayTracerPipeline& targetPipeline, char entryFunctionName[]) const
{
	targetPipeline.m_rayGenProgramGroups.resize(1);
	OptixProgramGroupOptions pgOptions = {};
	OptixProgramGroupDesc pgDesc = {};
	pgDesc.kind = OPTIX_PROGRAM_GROUP_KIND_RAYGEN;
	pgDesc.raygen.module = targetPipeline.m_module;
	pgDesc.raygen.entryFunctionName = entryFunctionName;
	char log[2048];
	size_t sizeofLog = sizeof(log);
	OPTIX_CHECK(optixProgramGroupCreate(m_optixContext,
		&pgDesc,
		1,
		&pgOptions,
		log, &sizeofLog,
		&targetPipeline.m_rayGenProgramGroups[0]
	));
	if (sizeofLog > 1) std::cout << log << std::endl;
}

void RayTracer::CreateModule(RayTracerPipeline& targetPipeline, char ptxCode[],
	char launchParamsName[]) const
{
	targetPipeline.m_launchParamsName = launchParamsName;

	targetPipeline.m_moduleCompileOptions.maxRegisterCount = 50;
	targetPipeline.m_moduleCompileOptions.optLevel = OPTIX_COMPILE_OPTIMIZATION_DEFAULT;
	targetPipeline.m_moduleCompileOptions.debugLevel = OPTIX_COMPILE_DEBUG_LEVEL_NONE;

	targetPipeline.m_pipelineCompileOptions = {};
	targetPipeline.m_pipelineCompileOptions.traversableGraphFlags = OPTIX_TRAVERSABLE_GRAPH_FLAG_ALLOW_SINGLE_GAS;
	targetPipeline.m_pipelineCompileOptions.usesMotionBlur = false;
	targetPipeline.m_pipelineCompileOptions.numPayloadValues = 2;
	targetPipeline.m_pipelineCompileOptions.numAttributeValues = 2;
	targetPipeline.m_pipelineCompileOptions.exceptionFlags = OPTIX_EXCEPTION_FLAG_NONE;
	targetPipeline.m_pipelineCompileOptions.pipelineLaunchParamsVariableName = launchParamsName;

	targetPipeline.m_pipelineLinkOptions.maxTraceDepth = 31;

	const std::string code = ptxCode;

	char log[2048];
	size_t sizeof_log = sizeof(log);
	OPTIX_CHECK(optixModuleCreateFromPTX(m_optixContext,
		&targetPipeline.m_moduleCompileOptions,
		&targetPipeline.m_pipelineCompileOptions,
		code.c_str(),
		code.size(),
		log, &sizeof_log,
		&targetPipeline.m_module
	));
	if (sizeof_log > 1) std::cout << log << std::endl;
}

void RayTracer::AssemblePipeline(RayTracerPipeline& targetPipeline) const
{
	std::vector<OptixProgramGroup> programGroups;
	for (auto* pg : targetPipeline.m_rayGenProgramGroups)
		programGroups.push_back(pg);
	for (auto* pg : targetPipeline.m_missProgramGroups)
		programGroups.push_back(pg);
	for (auto* pg : targetPipeline.m_hitGroupProgramGroups)
		programGroups.push_back(pg);

	char log[2048];
	size_t sizeofLog = sizeof(log);
	OPTIX_CHECK(optixPipelineCreate(m_optixContext,
		&targetPipeline.m_pipelineCompileOptions,
		&targetPipeline.m_pipelineLinkOptions,
		programGroups.data(),
		static_cast<int>(programGroups.size()),
		log, &sizeofLog,
		&targetPipeline.m_pipeline
	));
	if (sizeofLog > 1) std::cout << log << std::endl;

	OPTIX_CHECK(optixPipelineSetStackSize
	(/* [in] The pipeline to configure the stack size for */
		targetPipeline.m_pipeline,
		/* [in] The direct stack size requirement for direct
		   callables invoked from IS or AH. */
		2 * 1024,
		/* [in] The direct stack size requirement for direct
		   callables invoked from RG, MS, or CH.  */
		2 * 1024,
		/* [in] The continuation stack requirement. */
		2 * 1024,
		/* [in] The maximum depth of a traversable graph
		   passed to trace. */
		1));
	if (sizeofLog > 1) std::cout << log << std::endl;
}

void RayTracer::BuildShaderBindingTable(std::vector<TriangleMesh>& meshes, std::vector<std::pair<unsigned, cudaTextureObject_t>>& boundTextures, std::vector<cudaGraphicsResource_t>& boundResources)
{
	{
		// ------------------------------------------------------------------
		// build raygen records
		// ------------------------------------------------------------------
		std::vector<DefaultRenderingRayGenRecord> raygenRecords;
		for (int i = 0; i < m_defaultRenderingPipeline.m_rayGenProgramGroups.size(); i++) {
			DefaultRenderingRayGenRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultRenderingPipeline.m_rayGenProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			raygenRecords.push_back(rec);
		}
		m_defaultRenderingPipeline.m_rayGenRecordsBuffer.Upload(raygenRecords);
		m_defaultRenderingPipeline.m_sbt.raygenRecord = m_defaultRenderingPipeline.m_rayGenRecordsBuffer.DevicePointer();

		// ------------------------------------------------------------------
		// build miss records
		// ------------------------------------------------------------------
		std::vector<DefaultRenderingRayMissRecord> missRecords;
		for (int i = 0; i < m_defaultRenderingPipeline.m_missProgramGroups.size(); i++) {
			DefaultRenderingRayMissRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultRenderingPipeline.m_missProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			missRecords.push_back(rec);
		}
		m_defaultRenderingPipeline.m_missRecordsBuffer.Upload(missRecords);
		m_defaultRenderingPipeline.m_sbt.missRecordBase = m_defaultRenderingPipeline.m_missRecordsBuffer.DevicePointer();
		m_defaultRenderingPipeline.m_sbt.missRecordStrideInBytes = sizeof(DefaultRenderingRayMissRecord);
		m_defaultRenderingPipeline.m_sbt.missRecordCount = static_cast<int>(missRecords.size());

		// ------------------------------------------------------------------
		// build hit records
		// ------------------------------------------------------------------

		// we don't actually have any objects in this example, but let's
		// create a dummy one so the SBT doesn't have any null pointers
		// (which the sanity checks in compilation would complain about)
		const int numObjects = m_positionsBuffer.size();
		std::vector<DefaultRenderingRayHitRecord> hitGroupRecords;
		for (int i = 0; i < numObjects; i++) {
			for (int rayID = 0; rayID < static_cast<int>(DefaultRenderingRayType::RayTypeCount); rayID++) {
				DefaultRenderingRayHitRecord rec;
				OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultRenderingPipeline.m_hitGroupProgramGroups[rayID], &rec));
				rec.m_data.m_mesh.m_position = reinterpret_cast<glm::vec3*>(m_transformedPositionsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_triangle = reinterpret_cast<glm::uvec3*>(m_trianglesBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_normal = reinterpret_cast<glm::vec3*>(m_transformedNormalsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_tangent = reinterpret_cast<glm::vec3*>(m_transformedTangentsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_color = reinterpret_cast<glm::vec4*>(m_colorsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_texCoord = reinterpret_cast<glm::vec2*>(m_texCoordsBuffer[i].DevicePointer());

				rec.m_data.m_material.m_surfaceColor = meshes[i].m_surfaceColor;
				rec.m_data.m_material.m_roughness = meshes[i].m_roughness;
				rec.m_data.m_material.m_metallic = meshes[i].m_metallic;
				rec.m_data.m_material.m_albedoTexture = 0;
				rec.m_data.m_material.m_normalTexture = 0;
				rec.m_data.m_material.m_diffuseIntensity = meshes[i].m_diffuseIntensity;
				if (meshes[i].m_albedoTexture != 0)
				{
					bool duplicate = false;
					for (auto& boundTexture : boundTextures)
					{
						if (boundTexture.first == meshes[i].m_albedoTexture)
						{
							rec.m_data.m_material.m_albedoTexture = boundTexture.second;
							duplicate = true;
							break;
						}
					}
					if (!duplicate) {
#pragma region Bind output texture
						cudaArray_t textureArray;
						cudaGraphicsResource_t graphicsResource;
						CUDA_CHECK(GraphicsGLRegisterImage(&graphicsResource, meshes[i].m_albedoTexture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsReadOnly));
						CUDA_CHECK(GraphicsMapResources(1, &graphicsResource, nullptr));
						CUDA_CHECK(GraphicsSubResourceGetMappedArray(&textureArray, graphicsResource, 0, 0));
						struct cudaResourceDesc cudaResourceDesc;
						memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
						cudaResourceDesc.resType = cudaResourceTypeArray;
						cudaResourceDesc.res.array.array = textureArray;
						struct cudaTextureDesc cudaTextureDesc;
						memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
						cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
						cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
						cudaTextureDesc.filterMode = cudaFilterModeLinear;
						cudaTextureDesc.readMode = cudaReadModeElementType;
						cudaTextureDesc.normalizedCoords = 1;
						CUDA_CHECK(CreateTextureObject(&rec.m_data.m_material.m_albedoTexture, &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
						boundResources.push_back(graphicsResource);
						boundTextures.emplace_back(meshes[i].m_albedoTexture, rec.m_data.m_material.m_albedoTexture);
					}
				}
				if (meshes[i].m_normalTexture != 0)
				{
					bool duplicate = false;
					for (auto& boundTexture : boundTextures)
					{
						if (boundTexture.first == meshes[i].m_normalTexture)
						{
							rec.m_data.m_material.m_normalTexture = boundTexture.second;
							duplicate = true;
							break;
						}
					}
					if (!duplicate) {
#pragma region Bind output texture
						cudaArray_t textureArray;
						cudaGraphicsResource_t graphicsResource;
						CUDA_CHECK(GraphicsGLRegisterImage(&graphicsResource, meshes[i].m_normalTexture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsReadOnly));
						CUDA_CHECK(GraphicsMapResources(1, &graphicsResource, nullptr));
						CUDA_CHECK(GraphicsSubResourceGetMappedArray(&textureArray, graphicsResource, 0, 0));
						struct cudaResourceDesc cudaResourceDesc;
						memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
						cudaResourceDesc.resType = cudaResourceTypeArray;
						cudaResourceDesc.res.array.array = textureArray;
						struct cudaTextureDesc cudaTextureDesc;
						memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
						cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
						cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
						cudaTextureDesc.filterMode = cudaFilterModeLinear;
						cudaTextureDesc.readMode = cudaReadModeElementType;
						cudaTextureDesc.normalizedCoords = 1;
						CUDA_CHECK(CreateTextureObject(&rec.m_data.m_material.m_normalTexture, &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
						boundResources.push_back(graphicsResource);
						boundTextures.emplace_back(meshes[i].m_normalTexture, rec.m_data.m_material.m_normalTexture);
					}
				}
				hitGroupRecords.push_back(rec);
			}
		}
		m_defaultRenderingPipeline.m_hitGroupRecordsBuffer.Upload(hitGroupRecords);
		m_defaultRenderingPipeline.m_sbt.hitgroupRecordBase = m_defaultRenderingPipeline.m_hitGroupRecordsBuffer.DevicePointer();
		m_defaultRenderingPipeline.m_sbt.hitgroupRecordStrideInBytes = sizeof(DefaultRenderingRayHitRecord);
		m_defaultRenderingPipeline.m_sbt.hitgroupRecordCount = static_cast<int>(hitGroupRecords.size());
	}
	{
		// ------------------------------------------------------------------
		// build raygen records
		// ------------------------------------------------------------------
		std::vector<DefaultIlluminationEstimationRayGenRecord> raygenRecords;
		for (int i = 0; i < m_defaultIlluminationEstimationPipeline.m_rayGenProgramGroups.size(); i++) {
			DefaultIlluminationEstimationRayGenRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultIlluminationEstimationPipeline.m_rayGenProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			raygenRecords.push_back(rec);
		}
		m_defaultIlluminationEstimationPipeline.m_rayGenRecordsBuffer.Upload(raygenRecords);
		m_defaultIlluminationEstimationPipeline.m_sbt.raygenRecord = m_defaultIlluminationEstimationPipeline.m_rayGenRecordsBuffer.DevicePointer();

		// ------------------------------------------------------------------
		// build miss records
		// ------------------------------------------------------------------
		std::vector<DefaultIlluminationEstimationRayMissRecord> missRecords;
		for (int i = 0; i < m_defaultIlluminationEstimationPipeline.m_missProgramGroups.size(); i++) {
			DefaultIlluminationEstimationRayMissRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultIlluminationEstimationPipeline.m_missProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			missRecords.push_back(rec);
		}
		m_defaultIlluminationEstimationPipeline.m_missRecordsBuffer.Upload(missRecords);
		m_defaultIlluminationEstimationPipeline.m_sbt.missRecordBase = m_defaultIlluminationEstimationPipeline.m_missRecordsBuffer.DevicePointer();
		m_defaultIlluminationEstimationPipeline.m_sbt.missRecordStrideInBytes = sizeof(DefaultIlluminationEstimationRayMissRecord);
		m_defaultIlluminationEstimationPipeline.m_sbt.missRecordCount = static_cast<int>(missRecords.size());

		// ------------------------------------------------------------------
		// build hit records
		// ------------------------------------------------------------------

		// we don't actually have any objects in this example, but let's
		// create a dummy one so the SBT doesn't have any null pointers
		// (which the sanity checks in compilation would complain about)
		const int numObjects = m_positionsBuffer.size();
		std::vector<DefaultIlluminationEstimationRayHitRecord> hitGroupRecords;
		for (int i = 0; i < numObjects; i++) {
			for (int rayID = 0; rayID < static_cast<int>(DefaultIlluminationEstimationRayType::RayTypeCount); rayID++) {
				DefaultIlluminationEstimationRayHitRecord rec;
				OPTIX_CHECK(optixSbtRecordPackHeader(m_defaultIlluminationEstimationPipeline.m_hitGroupProgramGroups[rayID], &rec));
				rec.m_data.m_mesh.m_position = reinterpret_cast<glm::vec3*>(m_transformedPositionsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_triangle = reinterpret_cast<glm::uvec3*>(m_trianglesBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_normal = reinterpret_cast<glm::vec3*>(m_transformedNormalsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_tangent = reinterpret_cast<glm::vec3*>(m_transformedTangentsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_color = reinterpret_cast<glm::vec4*>(m_colorsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_texCoord = reinterpret_cast<glm::vec2*>(m_texCoordsBuffer[i].DevicePointer());

				rec.m_data.m_material.m_surfaceColor = meshes[i].m_surfaceColor;
				rec.m_data.m_material.m_roughness = meshes[i].m_roughness;
				rec.m_data.m_material.m_metallic = meshes[i].m_metallic;
				rec.m_data.m_material.m_albedoTexture = 0;
				rec.m_data.m_material.m_normalTexture = 0;
				rec.m_data.m_material.m_diffuseIntensity = meshes[i].m_diffuseIntensity;
				hitGroupRecords.push_back(rec);
			}
		}
		m_defaultIlluminationEstimationPipeline.m_hitGroupRecordsBuffer.Upload(hitGroupRecords);
		m_defaultIlluminationEstimationPipeline.m_sbt.hitgroupRecordBase = m_defaultIlluminationEstimationPipeline.m_hitGroupRecordsBuffer.DevicePointer();
		m_defaultIlluminationEstimationPipeline.m_sbt.hitgroupRecordStrideInBytes = sizeof(DefaultIlluminationEstimationRayHitRecord);
		m_defaultIlluminationEstimationPipeline.m_sbt.hitgroupRecordCount = static_cast<int>(hitGroupRecords.size());
	}
	{
		// ------------------------------------------------------------------
		// build raygen records
		// ------------------------------------------------------------------
		std::vector<RayMLVQRenderingRayGenRecord> raygenRecords;
		for (int i = 0; i < m_rayMLVQRenderingPipeline.m_rayGenProgramGroups.size(); i++) {
			RayMLVQRenderingRayGenRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_rayMLVQRenderingPipeline.m_rayGenProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			raygenRecords.push_back(rec);
		}
		m_rayMLVQRenderingPipeline.m_rayGenRecordsBuffer.Upload(raygenRecords);
		m_rayMLVQRenderingPipeline.m_sbt.raygenRecord = m_rayMLVQRenderingPipeline.m_rayGenRecordsBuffer.DevicePointer();

		// ------------------------------------------------------------------
		// build miss records
		// ------------------------------------------------------------------
		std::vector<RayMLVQRenderingRayMissRecord> missRecords;
		for (int i = 0; i < m_rayMLVQRenderingPipeline.m_missProgramGroups.size(); i++) {
			RayMLVQRenderingRayMissRecord rec;
			OPTIX_CHECK(optixSbtRecordPackHeader(m_rayMLVQRenderingPipeline.m_missProgramGroups[i], &rec));
			rec.m_data = nullptr; /* for now ... */
			missRecords.push_back(rec);
		}
		m_rayMLVQRenderingPipeline.m_missRecordsBuffer.Upload(missRecords);
		m_rayMLVQRenderingPipeline.m_sbt.missRecordBase = m_rayMLVQRenderingPipeline.m_missRecordsBuffer.DevicePointer();
		m_rayMLVQRenderingPipeline.m_sbt.missRecordStrideInBytes = sizeof(RayMLVQRenderingRayMissRecord);
		m_rayMLVQRenderingPipeline.m_sbt.missRecordCount = static_cast<int>(missRecords.size());

		// ------------------------------------------------------------------
		// build hit records
		// ------------------------------------------------------------------

		// we don't actually have any objects in this example, but let's
		// create a dummy one so the SBT doesn't have any null pointers
		// (which the sanity checks in compilation would complain about)
		const int numObjects = m_positionsBuffer.size();
		std::vector<RayMLVQRenderingRayHitRecord> hitGroupRecords;
		for (int i = 0; i < numObjects; i++) {
			for (int rayID = 0; rayID < static_cast<int>(RayMLVQRenderingRayType::RayTypeCount); rayID++) {
				RayMLVQRenderingRayHitRecord rec;
				OPTIX_CHECK(optixSbtRecordPackHeader(m_rayMLVQRenderingPipeline.m_hitGroupProgramGroups[rayID], &rec));
				rec.m_data.m_mesh.m_position = reinterpret_cast<glm::vec3*>(m_transformedPositionsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_triangle = reinterpret_cast<glm::uvec3*>(m_trianglesBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_normal = reinterpret_cast<glm::vec3*>(m_transformedNormalsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_tangent = reinterpret_cast<glm::vec3*>(m_transformedTangentsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_color = reinterpret_cast<glm::vec4*>(m_colorsBuffer[i].DevicePointer());
				rec.m_data.m_mesh.m_texCoord = reinterpret_cast<glm::vec2*>(m_texCoordsBuffer[i].DevicePointer());
				rec.m_data.m_enableMLVQ = meshes[i].m_enableMLVQ;
				if (meshes[i].m_enableMLVQ)
				{

				}
				else {
					rec.m_data.m_material.m_surfaceColor = meshes[i].m_surfaceColor;
					rec.m_data.m_material.m_roughness = meshes[i].m_roughness;
					rec.m_data.m_material.m_metallic = meshes[i].m_metallic;
					rec.m_data.m_material.m_albedoTexture = 0;
					rec.m_data.m_material.m_normalTexture = 0;
					rec.m_data.m_material.m_diffuseIntensity = meshes[i].m_diffuseIntensity;
					if (meshes[i].m_albedoTexture != 0)
					{
						bool duplicate = false;
						for (auto& boundTexture : boundTextures)
						{
							if (boundTexture.first == meshes[i].m_albedoTexture)
							{
								rec.m_data.m_material.m_albedoTexture = boundTexture.second;
								duplicate = true;
								break;
							}
						}
						if (!duplicate) {
#pragma region Bind output texture
							cudaArray_t textureArray;
							cudaGraphicsResource_t graphicsResource;
							CUDA_CHECK(GraphicsGLRegisterImage(&graphicsResource, meshes[i].m_albedoTexture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsReadOnly));
							CUDA_CHECK(GraphicsMapResources(1, &graphicsResource, nullptr));
							CUDA_CHECK(GraphicsSubResourceGetMappedArray(&textureArray, graphicsResource, 0, 0));
							struct cudaResourceDesc cudaResourceDesc;
							memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
							cudaResourceDesc.resType = cudaResourceTypeArray;
							cudaResourceDesc.res.array.array = textureArray;
							struct cudaTextureDesc cudaTextureDesc;
							memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
							cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
							cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
							cudaTextureDesc.filterMode = cudaFilterModeLinear;
							cudaTextureDesc.readMode = cudaReadModeElementType;
							cudaTextureDesc.normalizedCoords = 1;
							CUDA_CHECK(CreateTextureObject(&rec.m_data.m_material.m_albedoTexture, &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
							boundResources.push_back(graphicsResource);
							boundTextures.emplace_back(meshes[i].m_albedoTexture, rec.m_data.m_material.m_albedoTexture);
						}
					}
					if (meshes[i].m_normalTexture != 0)
					{
						bool duplicate = false;
						for (auto& boundTexture : boundTextures)
						{
							if (boundTexture.first == meshes[i].m_normalTexture)
							{
								rec.m_data.m_material.m_normalTexture = boundTexture.second;
								duplicate = true;
								break;
							}
						}
						if (!duplicate) {
#pragma region Bind output texture
							cudaArray_t textureArray;
							cudaGraphicsResource_t graphicsResource;
							CUDA_CHECK(GraphicsGLRegisterImage(&graphicsResource, meshes[i].m_normalTexture, GL_TEXTURE_2D, cudaGraphicsRegisterFlagsReadOnly));
							CUDA_CHECK(GraphicsMapResources(1, &graphicsResource, nullptr));
							CUDA_CHECK(GraphicsSubResourceGetMappedArray(&textureArray, graphicsResource, 0, 0));
							struct cudaResourceDesc cudaResourceDesc;
							memset(&cudaResourceDesc, 0, sizeof(cudaResourceDesc));
							cudaResourceDesc.resType = cudaResourceTypeArray;
							cudaResourceDesc.res.array.array = textureArray;
							struct cudaTextureDesc cudaTextureDesc;
							memset(&cudaTextureDesc, 0, sizeof(cudaTextureDesc));
							cudaTextureDesc.addressMode[0] = cudaAddressModeWrap;
							cudaTextureDesc.addressMode[1] = cudaAddressModeWrap;
							cudaTextureDesc.filterMode = cudaFilterModeLinear;
							cudaTextureDesc.readMode = cudaReadModeElementType;
							cudaTextureDesc.normalizedCoords = 1;
							CUDA_CHECK(CreateTextureObject(&rec.m_data.m_material.m_normalTexture, &cudaResourceDesc, &cudaTextureDesc, nullptr));
#pragma endregion
							boundResources.push_back(graphicsResource);
							boundTextures.emplace_back(meshes[i].m_normalTexture, rec.m_data.m_material.m_normalTexture);
						}
					}
				}
				hitGroupRecords.push_back(rec);
			}
		}
		m_rayMLVQRenderingPipeline.m_hitGroupRecordsBuffer.Upload(hitGroupRecords);
		m_rayMLVQRenderingPipeline.m_sbt.hitgroupRecordBase = m_rayMLVQRenderingPipeline.m_hitGroupRecordsBuffer.DevicePointer();
		m_rayMLVQRenderingPipeline.m_sbt.hitgroupRecordStrideInBytes = sizeof(RayMLVQRenderingRayHitRecord);
		m_rayMLVQRenderingPipeline.m_sbt.hitgroupRecordCount = static_cast<int>(hitGroupRecords.size());
	}
}
