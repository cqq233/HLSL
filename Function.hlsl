#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

#if SHADER_LIBRARY_VERSION_MAJOR < 9
// These functions were added in URP v9.x versions, if we want to support URP versions before, we need to handle it
// If you're in v10 you could remove this if you don't care about supporting prior versions.
// (Note, also using GetWorldSpaceViewDir in Vertex Shader)

// Computes the world space view direction (pointing towards the viewer).
float3 GetWorldSpaceViewDir(float3 positionWS) {
	if (unity_OrthoParams.w == 0) {
		// Perspective
		return _WorldSpaceCameraPos - positionWS;
	} else {
		// Orthographic
		float4x4 viewMat = GetWorldToViewMatrix();
		return viewMat[2].xyz;
	}
}

half3 GetWorldSpaceNormalizeViewDir(float3 positionWS) {
	float3 viewDir = GetWorldSpaceViewDir(positionWS);
	if (unity_OrthoParams.w == 0) {
		// Perspective
		return half3(normalize(viewDir));
	} else {
		// Orthographic
		return half3(viewDir);
	}
}
#endif



void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData) {
	inputData = (InputData)0; // avoids "not completely initalized" errors

	inputData.positionWS = input.positionWS;
	
	#ifdef _NORMALMAP
		half3 viewDirWS = half3(input.normalWS.w, input.tangentWS.w, input.bitangentWS.w);
		inputData.normalWS = TransformTangentToWorld(normalTS,half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz));
	#else
		half3 viewDirWS = GetWorldSpaceNormalizeViewDir(inputData.positionWS);
		inputData.normalWS = input.normalWS;
	#endif

	inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
	viewDirWS = SafeNormalize(viewDirWS);

	inputData.viewDirectionWS = viewDirWS;

	#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
		inputData.shadowCoord = input.shadowCoord;
	#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
		inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
	#else
		inputData.shadowCoord = float4(0, 0, 0, 0);
	#endif

	// Fog
	#ifdef _ADDITIONAL_LIGHTS_VERTEX
		inputData.fogCoord = input.fogFactorAndVertexLight.x;
    	inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
	#else
		inputData.fogCoord = input.fogFactor;
		inputData.vertexLighting = half3(0, 0, 0);
	#endif

	/* in v11/v12?, could use this :
	#ifdef _ADDITIONAL_LIGHTS_VERTEX
		inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactorAndVertexLight.x);
		inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
	#else
		inputData.fogCoord = InitializeInputDataFog(float4(inputData.positionWS, 1.0), input.fogFactor);
		inputData.vertexLighting = half3(0, 0, 0);
	#endif
	// Which currently just seems to force re-evaluating fog per fragment
	*/

	inputData.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, inputData.normalWS);
	inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
	inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);
}

TEXTURE2D(_SpecGlossMap); 	SAMPLER(sampler_SpecGlossMap);

// Functions
half4 SampleSpecularSmoothness(float2 uv, half alpha, half4 specColor, TEXTURE2D_PARAM(specMap, sampler_specMap)) {
	half4 specularSmoothness = half4(0.0h, 0.0h, 0.0h, 1.0h);
	#ifdef _SPECGLOSSMAP
		specularSmoothness = SAMPLE_TEXTURE2D(specMap, sampler_specMap, uv) * specColor;
	#elif defined(_SPECULAR_COLOR)
		specularSmoothness = specColor;
	#endif

	#ifdef _GLOSSINESS_FROM_BASE_ALPHA
		specularSmoothness.a = exp2(10 * alpha + 1);
	#else
		specularSmoothness.a = exp2(10 * specularSmoothness.a + 1);
	#endif
	return specularSmoothness;
}

void InitializeSurfaceData(Varyings IN, out SurfaceData surfaceData){
	surfaceData = (SurfaceData)0; // avoids "not completely initalized" errors

	half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);

	#ifdef _ALPHATEST_ON
		// Alpha Clipping
		clip(baseMap.a - _Cutoff);
	#endif

	half4 diffuse = baseMap * _BaseColor * IN.color;
	surfaceData.albedo = diffuse.rgb;
	surfaceData.normalTS = SampleNormal(IN.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap));
	surfaceData.emission = SampleEmission(IN.uv, _EmissionColor.rgb, TEXTURE2D_ARGS(_EmissionMap, sampler_EmissionMap));

	half4 specular = SampleSpecularSmoothness(IN.uv, diffuse.a, _SpecColor, TEXTURE2D_ARGS(_SpecGlossMap, sampler_SpecGlossMap));
	surfaceData.specular = specular.rgb;
	surfaceData.smoothness = specular.a * _Smoothness;
}