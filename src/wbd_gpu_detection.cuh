/**
 * @file	wbd_gpu_detection.cuh
 * @brief Waldboost detector gpu functions for object detection.
 *
 * @author Pavel Macenauer <macenauer.p@gmail.com>
 */

#ifndef CUH_WBD_GPU_DETECTION
#define CUH_WBD_GPU_DETECTION

#include "wbd_general.h"
#include "wbd_structures.h"

#include "cuda_runtime.h"

namespace wbd
{
	namespace gpu
	{		
		namespace detection
		{
			/** @brief Detector stages. */
			__constant__ Stage stages[WB_STAGE_COUNT];

			/** @brief Loads stages into constant memory. 
			 *
			 * @details Constant memory is name-bound, therefore we must bind it by calling this function.
			 *
			 * @return Void.
			 */
			void initDetectionStages();

			/** @brief Evaluates stages for a given coordinate
			 *
			 * @details Evaluates stages for a given coordinate from a starting stage to an end stage,
			 *			accumulates a response and determines if given sample is an object.
			 *
			 * @param x				X-coordinate.
			 * @param y				Y-coordinate.
			 * @param response		Accumulated reponse.
			 * @param startStage	Starting stage.
			 * @param endStage		Ending stage.
			 * @return				Detection success.
			 */
			__device__ bool eval(cudaTextureObject_t texture, cudaTextureObject_t alphas, uint32 x, uint32 y, float* response, uint16 startStage, uint16 endStage);

			/** @brief Evaluates LBP for a given coordinate
			 *
			 * @details Evaluates LBP for a given coordinate with a given stage and returns a response.
			 *
			 * @param x				X-coordinate.
			 * @param y				Y-coordinate.
			 * @param stage			Classifier stage.
			 * @return				A response.
			 */
			__device__ float evalLBP(cudaTextureObject_t texture, cudaTextureObject_t alphas, uint32 x, uint32 y, Stage* stage);

			/** @brief Sums regions for LBP calculation.
			 *
			 * @details Interpolates image regions (1x1, 2x1, 1x2, 2x2) for LBP calculation. Uses
			 *			texture unit bilinear interpolation capabilities.
			 *
			 * @param values	Values used for LBP calculation.
			 * @param x			X-coordinate.
			 * @param y			Y-coordinate.
			 * @param stage		Classifier stage.
			 * @return			Void.
			 */
			__device__ void sumRegions(cudaTextureObject_t texture, float* values, uint32 x, uint32 y, Stage* stage);

			namespace prefixsum
			{
				/** @brief Initial survivor detection processing
				 *
				 * @details Processes detections on an image from the first stage (of the waldboost detector).
				 *			Processes the whole image and outputs the remaining surviving positions after reaching
				 *			the ending stage.
				 *
				 * @param texture			Pyramid image texture.
				 * @param alphas			Alpha texture.
				 * @param x					X-coordinate.
				 * @param y					Y-coordinate
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory offset.
				 * @param survivors			Output array of surviving positions.
				 * @param survivorCount		Number of surviving positions.
				 * @param survivorScanArray	Helper array to count prefixsum.
				 * @param endStage			Ending stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectSurvivorsInit
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		x,
					uint32 const&		y,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					uint32 const&		blockSize,
					SurvivorData*		survivors,
					uint32&				survivorCount,
					uint32*				survivorScanArray,
					uint16				endStage
				);

				/** @brief Survivor detection processing
				 *
				 * @details Processes detections on an image from a set starting stage (of the waldboost detector).
				 *			Processes only positions in the initSurvivors array and outputs still surviving positions
				 *			after reaching the ending stage.
				 *
				 * @param texture			Pyramid image texture.
				 * @param alphas			Alpha texture.
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory offset.
				 * @param survivors			Output and input array of surviving positions.
				 * @param survivorCount		Number of surviving positions.
				 * @param survivorScanArray	Helper array to count prefixsum.
				 * @param startStage		Starting stage of the waldboost detector.
				 * @param endStage			Ending stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectSurvivors
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					uint32 const&		blockSize,
					SurvivorData*		survivors,
					uint32&				survivorCount,
					uint32*				survivorScanArray,
					uint16				startStage,
					uint16				endStage
				);

				/** @brief Final detection processing
				 *
				 * @details Processes detections on an image beginning at a starting stage, until the end.
				 *			Processes only given surviving positions and outputs detections, which can then
				 *			be displayed.
				 *
				 * @param texture			Pyramid image texture.
				 * @param alphas			Alpha texture.
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory offset.
				 * @param survivors			Input array of surviving positions.
				 * @param detections		Output array of detections.
				 * @param detectionCount	Number of detections.
				 * @param startStage		Starting stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectDetections
				(
					cudaTextureObject_t	texture,
					cudaTextureObject_t	alphas,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					SurvivorData*		survivors,
					Detection*			detections,
					uint32*				detectionCount,
					uint16				startStage
				);

				/** @brief Runs detection using prefixsum optimalization. 
				 *
				 * @details Runs the detection using prefixsum optimalizaton, which is currently only used for 
				 *			initial step, later on atomic methods are used due to thread management, because we
				 *			we can discard threads early on. With prefixsum, threads are all used.
				 *
				 * @param texture			Input texture.
				 * @param alphas			Detector alphas texture.
				 * @param detections		Output detections.
				 * @param detectionCount	Output detection count.
				 * @return					Void.
				 */
				__global__ void detect(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					Detection*			detections,
					uint32*				detectionCount
				);
			} // namespace prefixsum

			namespace atomicshared
			{
				/** @brief Initial survivor detection processing
				 *
				 * @details Processes detections on an image from the first stage (of the waldboost detector).
				 *			Processes the whole image and outputs the remaining surviving positions after reaching
				 *			the ending stage. Stores surviving count and info in local memory.
				 *
				 * @param texture				Pyramid image texture.
				 * @param alphas				Alpha texture.
				 * @param x						X-coordinate.
				 * @param y						Y-coordinate
				 * @param threadId				Thread id.
				 * @param localSurvivors		Global memory offset.
				 * @param localSurvivorCount	Output array of surviving positions.				 
				 * @return						Void.
				 */
				__device__ void detectSurvivorsInit
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		x,
					uint32 const&		y,
					uint32 const&		threadId,
					SurvivorData*		localSurvivors,
					uint32*				localSurvivorCount,
					uint16				endStage
				);

				/** @brief Atomic shared memSurvivor detection processing
				 *
				 * @details Processes detections on an image from a set starting stage (of the waldboost detector)
				 * 			until an end stage. Uses shared memory for input and output survivors.
				 *
				 * @param texture				Pyramid image texture.
				 * @param alphas				Alpha texture.
				 * @param threadId				Thread id.				 
				 * @param localSurvivors		Output and input array of surviving positions.
				 * @param localSurvivorCount	Helper array to count prefixsum.
				 * @param startStage			Starting stage of the waldboost detector.
				 * @param endStage				Ending stage of the waldboost detector.
				 * @return						Void.
				 */
				__device__ void detectSurvivors
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		threadId,
					SurvivorData*		localSurvivors,
					uint32*				localSurvivorCount,
					uint16				startStage,
					uint16				endStage
				);

				/** @brief Atomic shared memory final detection.
				 *
				 * @details Final detection processing. Takes surviving detections on the input and processes
				 * 			them from a given starting stage until the end. Uses atomic instructions and shared memory.				  			
				 *
				 * @param texture			Pyramid image texture.
				 * @param alphas			Alpha texture.
				 * @param threadId			Thread id.				 
				 * @param localSurvivors	Input array of surviving positions.
				 * @param detections		Output array of detections.
				 * @param detectionCount	Number of detections.
				 * @param startStage		Starting stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectDetections
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		threadId,
					SurvivorData*		localSurvivors,
					Detection*			detections,
					uint32*				detectionCount,
					uint16				startStage
				);

				/** @brief Atomic shared memory detection kernel. 
				 *
				 * @details Kernel wrapper for atomic shared memory detection. Uses shared memory
				 *			for storing surviving detections and an atomic counter for each block.
				 *
				 * @param texture			Image texture.
				 * @param alphas			Detector alphas store as texture.
				 * @param width				Image width.
				 * @param height			Image height.
				 * @param detections		Detection output in global memory.
				 * @param detectionCount	Number of detections.
				 */
				__global__ void detect
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32				width,
					uint32				height,
					Detection*			detections,
					uint32*				detectionCount
				);
			} // namespace atomicshared

			namespace atomicglobal
			{
				/** @brief Initial survivor detection processing
				 *
				 * @details Processes detections on an image from the first stage (of the waldboost detector).
				 *			Processes the whole image and outputs the remaining surviving positions after reaching
				 *			the ending stage.
				 *
				 * @param texture			Pyramid image texture.
				 * @param alphas				Alpha texture.
				 * @param x					X-coordinate.
				 * @param y					Y-coordinate
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory offset.
				 * @param globalSurvivors	Output array of surviving positions.
				 * @param survivorCount		Number of surviving positions.
				 * @param endStage			Ending stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectSurvivorsInit
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		x,
					uint32 const&		y,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					SurvivorData*		globalSurvivors,
					uint32*				survivorCount,
					uint16				endStage);

				/** @brief Survivor detection processing
				 *
				 * @details Intermediate detection function, processes surviving detections starting at a given
				 *			stage and ending at another stage. Uses global memory for storing surviving detections.
				 *			Every block has a defined offset inside the global memory array.
				 *
				 * @param texture			Image texture.
				 * @param alphas			Alpha texture.
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory block offset.
				 * @param globalSurvivors	Global memory detection survivor array.
				 * @param survivorCount		Number of surviving positions. Different for each block (stored in shared memory).				 
				 * @param startStage		Starting stage of the waldboost detector.
				 * @param endStage			Ending stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectSurvivors
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					SurvivorData*		globalSurvivors,
					uint32*				survivorCount,
					uint16				startStage,
					uint16				endStage
				);

				/** @brief Final detection processing
				 *
				 * @details Processes detections on an image beginning at a starting stage, until the end.
				 *			Processes only given surviving positions and outputs detections, which can then
				 *			be displayed.
				 *
				 * @param texture			Image texture.
				 * @param alphas			Alpha texture.
				 * @param threadId			Thread id.
				 * @param globalOffset		Global memory offset.
				 * @param survivors			Input array of surviving positions.
				 * @param detections		Output array of detections.
				 * @param detectionCount	Number of detections.
				 * @param startStage		Starting stage of the waldboost detector.
				 * @return					Void.
				 */
				__device__ void detectDetections
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					uint32 const&		threadId,
					uint32 const&		globalOffset,
					SurvivorData*		globalSurvivors,
					Detection*			detections,
					uint32*				detectionCount,
					uint16				startStage
				);

				/** @brief Atomic global memory kernel wrapper.
				 *
				 * @details Processes detections with survivors stored in global memory. Uses a counter
				 *			stored in shared memory and a global memory with offsets for every block for
				 *			storing surviving detections. This way the counter is distributed between blocks.
				 *
				 * @param texture		Image texture.
				 * @param alphas		Detector alphas texture.
				 * @param width			Image width.
				 * @param height		Image height.
				 * @param survivors		Global memory array of survivors.
				 * @param detections	Global memory array of detections.
				 * @param detectionCount Detection count in global memory.
				 * @return				Void.
				 */
				__global__ void detect
				(
					cudaTextureObject_t texture,
					cudaTextureObject_t alphas,
					const uint32		width,
					const uint32		height,
					SurvivorData*		survivors,
					Detection*			detections,
					uint32*				detectionCount
				);

			} // namespace atomicglobal

		} // namespace detection	
	} // namespace gpu
} // namespace wbd

#endif // CUH_WBD_GPU_DETECTION
