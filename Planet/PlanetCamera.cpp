#include "PlanetCamera.h"
#include "GameInput.h"

PlanetCamera::PlanetCamera(const PlanetCameraSetting& settings, Camera& camera)
	: CameraController(camera)
	, _settings(settings)
	, _planetNormal(0,0,0)
	, _planetTangent(0,0,0)
	, _currentYaw(0.0)
	, _currentPitch(0.0)
	, _currentHeight(0.0)
	, _currentPhi(0.0)
	, _currentTheta(0.0)
{
	camera.SetPosition(float3(0, 1, 0));
	camera.SetLookDirection(Vector3(0, 0, 1), Vector3(0, 1, 0));
}

void PlanetCamera::Update(float deltaTime)
{
	UpdateCameraUpVector();
	Rotation(deltaTime);
	Movement(deltaTime);
}

void PlanetCamera::Movement(const float deltaTime)
{
	_currentHeight += GameInput::GetAnalogInput(GameInput::kAnalogMouseScroll) * _settings._movementSpeed*deltaTime;
	_currentHeight = _currentHeight < _settings._minHeight ? _settings._minHeight : _currentHeight;
	_currentHeight = _currentHeight > _settings._maxHeight ? _settings._maxHeight : _currentHeight;

	const Vector3 center = _settings._planetCenter;
	const Vector3 fowardAxis = static_cast<Vector3>(XMVector3Cross(_planetTangent, _planetNormal));
	const Vector3 newPosition = center + _planetNormal * _currentHeight;

	m_TargetCamera.SetPosition(newPosition);
}

void PlanetCamera::Rotation(const float deltaTime)
{
	_currentYaw += GameInput::GetAnalogInput(GameInput::kAnalogMouseX) * _settings._rotationSpeed*deltaTime;
	_currentPitch += GameInput::GetAnalogInput(GameInput::kAnalogMouseY) * _settings._rotationSpeed*deltaTime;

	if (Math::XMConvertToDegrees(_currentPitch) > 89.0f)
	{
		_currentPitch = Math::XMConvertToRadians(89.0);
	}

	if (Math::XMConvertToDegrees(_currentPitch) < -89.0f)
	{
		_currentPitch = Math::XMConvertToRadians(-89.0f);
	}

	float3 cameraDirection = float3(-cosf(_currentPitch) * sinf(_currentYaw), sinf(_currentPitch), -cosf(_currentPitch) * cosf(_currentYaw));
	float3 up = float3(0.0f, 1.0f, 0.0f);

	m_TargetCamera.SetLookDirection(cameraDirection, up);
	m_TargetCamera.Update();
}

void PlanetCamera::UpdateCameraUpVector()
{
	const Vector3 center = _settings._planetCenter;
	const Vector3 position = m_TargetCamera.GetPosition();
	const Vector3 direction = Normalize(position - center);
	_planetNormal = direction;
	const float cosTheta = Dot(_planetNormal, float3(1,0,0));
	_planetTangent = float3(cosTheta, 0.0f, sqrtf(1.0f - cosTheta * cosTheta));
}
