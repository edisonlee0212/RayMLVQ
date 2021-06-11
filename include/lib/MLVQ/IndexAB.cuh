#pragma once
#include <Optix7.hpp>
#include <SharedCoordinates.cuh>
#include <VectorColor.cuh>
namespace RayTracerFacility
{
	struct IndexAB
	{
		// the data array of 1D colour index slices
		CudaBuffer m_indexAbBasisBuffer;
		int* m_indexAbBasis;
		// current number of stored 1D index slices
		int m_numOfIndexSlices;
		// length of index slice
		int m_lengthOfSlice;

		VectorColor m_ab;

		void Init(const int& lengthOfSlice)
		{
			assert(lengthOfSlice > 0);
			m_lengthOfSlice = lengthOfSlice;
			m_numOfIndexSlices = 0;
		}
		
		// get a single color value specified by sliceindex, slice position and posAB (0,1)
		__device__
			float Get(const int& sliceIndex, const int& posBeta, const int& posAB, SharedCoordinates& tc) const
		{
			assert(sliceIndex >= 0 && sliceIndex < m_numOfIndexSlices);
			assert(posBeta >= 0 && posBeta < m_lengthOfSlice);

			return m_ab.Get(m_indexAbBasis[sliceIndex * m_lengthOfSlice + posBeta], posAB, tc);
		}
		
		// Here beta is specified by 'tc'
		__device__
			void GetVal(const int& sliceIndex, glm::vec3& out, SharedCoordinates& tc) const
		{
			out[0] = (1.f - tc.m_wBeta) * Get(sliceIndex, tc.m_iBeta, 0, tc) +
				tc.m_wBeta * Get(sliceIndex, tc.m_iBeta + 1, 0, tc);
			out[1] = (1.f - tc.m_wBeta) * Get(sliceIndex, tc.m_iBeta, 1, tc) +
				tc.m_wBeta * Get(sliceIndex, tc.m_iBeta + 1, 1, tc);
		}
	};
}