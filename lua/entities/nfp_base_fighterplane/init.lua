include( "sv_ai.lua" )

-- ============================================================
-- STEERING
-- ============================================================

function ENT:ApproachTargetAngle( nfpTargetAngle, nfpOverridePitch, nfpOverrideYaw, nfpOverrideRoll, nfpFreeMovement )
	local nfpLocalAngles = self:WorldToLocalAngles( nfpTargetAngle )

	local nfpLocalAngPitch = nfpLocalAngles.p
	local nfpLocalAngYaw   = nfpLocalAngles.y
	local nfpLocalAngRoll  = nfpLocalAngles.r

	local nfpTargetFwd = nfpTargetAngle:Forward()
	local nfpFwd       = self:GetForward()

	local nfpAngDiff = math.deg( math.acos( math.Clamp( nfpFwd:Dot( nfpTargetFwd ), -1, 1 ) ) )

	local nfpWingFinFadeOut = math.max( (90 - nfpAngDiff) / 90, 0 )
	local nfpRudderFadeOut  = math.min( math.max( (120 - nfpAngDiff) / 120, 0 ) * 3, 1 )

	local nfpAngVel = self:GetPhysicsObject():GetAngleVelocity()

	local nfpSmoothPitch = math.Clamp( math.Clamp( nfpAngVel.y / 100, -0.25, 0.25 ) / math.abs( nfpLocalAngPitch ), -1, 1 )
	local nfpSmoothYaw   = math.Clamp( math.Clamp( nfpAngVel.z / 100, -0.25, 0.25 ) / math.abs( nfpLocalAngYaw ),   -1, 1 )

	local nfpPitch = math.Clamp( -nfpLocalAngPitch / 10 + nfpSmoothPitch, -1, 1 )
	local nfpYaw   = math.Clamp( -nfpLocalAngYaw   / 2  + nfpSmoothYaw,  -1, 1 ) * nfpRudderFadeOut
	local nfpRoll  = math.Clamp( (-math.Clamp( nfpLocalAngYaw * 16, -90, 90 ) + nfpLocalAngRoll * nfpRudderFadeOut * 0.75) * nfpWingFinFadeOut / 180, -1, 1 )

	if nfpFreeMovement then
		nfpRoll = math.Clamp( -nfpLocalAngYaw * nfpWingFinFadeOut / 180, -1, 1 )
	end

	if nfpOverridePitch and nfpOverridePitch ~= 0 then nfpPitch = nfpOverridePitch end
	if nfpOverrideYaw   and nfpOverrideYaw   ~= 0 then nfpYaw   = nfpOverrideYaw   end
	if nfpOverrideRoll  and nfpOverrideRoll  ~= 0 then nfpRoll  = nfpOverrideRoll  end

	self:SetSteer( Vector( math.Clamp( nfpRoll * 1.25, -1, 1 ), math.Clamp( -nfpPitch * 1.25, -1, 1 ), -nfpYaw ) )
end

-- ============================================================
-- AERODYNAMICS
-- ============================================================

function ENT:CalcAero( phys, deltatime, EntTable )
	if not EntTable then
		EntTable = self:GetTable()
	end

	-- Reads _nfpAITargetAng written by sv_ai.lua RunAI()
	if EntTable._nfpAITargetAng then
		self:ApproachTargetAngle( EntTable._nfpAITargetAng )
	end

	local nfpWorldGravity = self:GetWorldGravity()
	local nfpWorldUp      = self:GetWorldUp()
	local nfpSteer        = self:GetSteer()

	local nfpStability, nfpInvStability = self:GetStability()

	local nfpFwd  = self:GetForward()
	local nfpLeft = -self:GetRight()
	local nfpUp   = self:GetUp()

	local nfpVel    = self:GetVelocity()
	local nfpVelFwd = nfpVel:GetNormalized()

	local nfpPitchPull = math.max( (math.deg( math.acos( math.Clamp( nfpWorldUp:Dot( nfpUp ),  -1, 1 ) ) ) - 90) / 90, 0 )
	local nfpYawPull   = (math.deg( math.acos( math.Clamp( nfpWorldUp:Dot( nfpLeft ), -1, 1 ) ) ) - 90) / 90

	local nfpGravMul = (nfpWorldGravity / 600) * 0.25

	if self:IsDestroyed() then
		nfpSteer     = phys:GetAngleVelocity() / 200
		nfpPitchPull = (math.deg( math.acos( math.Clamp( nfpWorldUp:Dot( nfpUp ), -1, 1 ) ) ) - 90) / 90
		nfpGravMul   = nfpWorldGravity / 600
	end

	local nfpGravityPitch = math.abs( nfpPitchPull ) ^ 1.25 * self:Sign( nfpPitchPull ) * nfpGravMul * EntTable.GravityTurnRatePitch
	local nfpGravityYaw   = math.abs( nfpYawPull )   ^ 1.25 * self:Sign( nfpYawPull )   * nfpGravMul * EntTable.GravityTurnRateYaw

	local nfpStallMul   = math.min( (-math.min( nfpVel.z + EntTable.StallVelocity, 0 ) / 100) * EntTable.StallForceMultiplier, EntTable.StallForceMax )
	local nfpStallPitch = 0
	local nfpStallYaw   = 0

	if nfpStallMul > 0 then
		if nfpInvStability < 1 then
			nfpStallPitch = nfpPitchPull * nfpGravMul * nfpStallMul
			nfpStallYaw   = nfpYawPull   * nfpGravMul * nfpStallMul
		else
			local nfpStallPitchDir = self:Sign( math.deg( math.acos( math.Clamp( -nfpVelFwd:Dot( self:LocalToWorldAngles( Angle(-10,0,0) ):Up() ), -1, 1 ) ) ) - 90 )
			local nfpStallYawDir   = self:Sign( math.deg( math.acos( math.Clamp( -nfpVelFwd:Dot( nfpLeft ), -1, 1 ) ) ) - 90 )

			local nfpStallPitchPull = ((90 - math.abs( math.deg( math.acos( math.Clamp( -nfpWorldUp:Dot( nfpUp ),   -1, 1 ) ) ) - 90 )) / 90) * nfpStallPitchDir
			local nfpStallYawPull   = ((90 - math.abs( math.deg( math.acos( math.Clamp( -nfpWorldUp:Dot( nfpLeft ), -1, 1 ) ) ) - 90 )) / 90) * nfpStallYawDir * 0.5

			nfpStallPitch = nfpStallPitchPull * nfpGravMul * nfpStallMul
			nfpStallYaw   = nfpStallYawPull   * nfpGravMul * nfpStallMul
		end
	end

	local nfpPitch = math.Clamp( nfpSteer.y - nfpGravityPitch, -1, 1 ) * EntTable.TurnRatePitch * 3 * nfpStability - nfpStallPitch * nfpInvStability
	local nfpYaw   = math.Clamp( nfpSteer.z * 4 + nfpGravityYaw, -1, 1 ) * EntTable.TurnRateYaw * nfpStability + nfpStallYaw * nfpInvStability
	local nfpRoll  = math.Clamp( nfpSteer.x * 1.5, -1, 1 ) * EntTable.TurnRateRoll * 12 * nfpStability

	local nfpVelL = self:WorldToLocal( self:GetPos() + nfpVel )

	local nfpSlipMul = 1 - math.Clamp( math.max( math.abs( nfpVelL.x ) - EntTable.MaxPerfVelocity, 0 ) / math.max( EntTable.MaxVelocity - EntTable.MaxPerfVelocity, 0 ), 0, 1 )

	local nfpMulZ = (math.max( math.deg( math.acos( math.Clamp( nfpVelFwd:Dot( nfpFwd ),  -1, 1 ) ) ) - EntTable.MaxSlipAnglePitch * nfpSlipMul * math.abs( nfpSteer.y ), 0 ) / 90) * 0.3
	local nfpMulY = (math.max( math.abs( math.deg( math.acos( math.Clamp( nfpVelFwd:Dot( nfpLeft ), -1, 1 ) ) ) - 90 ) - EntTable.MaxSlipAngleYaw * nfpSlipMul * math.abs( nfpSteer.z ), 0 ) / 90) * 0.15

	local nfpLift = -math.min( (math.deg( math.acos( math.Clamp( nfpWorldUp:Dot( nfpUp ), -1, 1 ) ) ) - 90) / 180, 0 ) * (nfpWorldGravity / (1 / deltatime))

	return Vector( 0, -nfpVelL.y * nfpMulY, nfpLift - nfpVelL.z * nfpMulZ ) * nfpStability, Vector( nfpRoll, nfpPitch, nfpYaw )
end

-- ============================================================
-- PHYSICS SIMULATE
-- ============================================================

function ENT:PhysicsSimulate( phys, deltatime )
	local EntTable     = self:GetTable()
	local nfpAero, nfpTorque = self:CalcAero( phys, deltatime, EntTable )
	if self:GetEngineActive() then phys:Wake() end
	local nfpThrust       = math.max( self:GetThrustStrenght(), 0 ) * EntTable.MaxThrust * 100
	local nfpForceLinear  = (nfpAero * 10000 * EntTable.ForceLinearMultiplier + Vector( nfpThrust, 0, 0 )) * deltatime
	local nfpForceAngle   = (nfpTorque * 25 * EntTable.ForceAngleMultiplier - phys:GetAngleVelocity() * 1.5 * EntTable.ForceAngleDampingMultiplier) * deltatime * 250
	return self:PhysicsSimulateOverride( nfpForceAngle, nfpForceLinear, phys, deltatime, SIM_LOCAL_ACCELERATION )
end

function ENT:PhysicsSimulateOverride( nfpForceAngle, nfpForceLinear, phys, deltatime, simulate )
	return nfpForceAngle, nfpForceLinear, simulate
end

-- ============================================================
-- SKY COLLISION
-- ============================================================

function ENT:OnSkyCollide( data, PhysObj )
	local nfpNewVelocity = self:VectorSubtractNormal( data.HitNormal, data.OurOldVelocity ) - data.HitNormal * math.Clamp( self:GetThrustStrenght() * self.MaxThrust, 250, 800 )
	PhysObj:SetVelocityInstantaneous( nfpNewVelocity )
	PhysObj:SetAngleVelocityInstantaneous( data.OurOldAngularVelocity )
	self:FreezeStability()
	return true
end
