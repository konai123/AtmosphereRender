#pragma once
#include "pch.h"
#include "CameraController.h"
#include "Camera.h"
#include "types.h"

class PlanetCamera  : public CameraController
{
public:
	struct PlanetCameraSetting {
		explicit PlanetCameraSetting(const float3& planetCenter, const float minHeight, const float maxHeight, const float rotationSpeed = 1.0, const float movementSpeed = 1.0)
		:_planetCenter(planetCenter)
		,_minHeight(minHeight)
		,_maxHeight(maxHeight)
		,_rotationSpeed(rotationSpeed)
		,_movementSpeed(movementSpeed)
		{}

		float3 _planetCenter;
		float _minHeight;
		float _maxHeight;
		float _rotationSpeed;
		float _movementSpeed;
	};

public:
	explicit PlanetCamera(const PlanetCameraSetting& settings, Camera& camera);

public:
	virtual void Update(float deltaTime) override;

private:
	void Movement(const float deltaTime);
	void Rotation(const float deltaTime);
	void UpdateCameraUpVector();

private:
	PlanetCameraSetting _settings;
	Vector3 _planetNormal;
	Vector3 _planetTangent;

	float _currentYaw;
	float _currentPitch;

	float _currentHeight;
	float _currentPhi;
	float _currentTheta;
};

