include( "shared.lua" )

function ENT:OnSpawn()
	self:RegisterTrail( Vector(-25,-219,84), 0, 20, 2, 1000, 600 )
	self:RegisterTrail( Vector(-25, 219,84), 0, 20, 2, 1000, 600 )
end

function ENT:OnFrame()
	local nfpFT = RealFrameTime()
	self:NFP_AnimControlSurfaces( nfpFT )
	self:NFP_AnimLandingGear( nfpFT )
	self:NFP_AnimRotor( nfpFT )
end

function ENT:NFP_AnimRotor( nfpFrametime )
	if not self.RotorRPM then return end
	local nfpPhysRot = self.RotorRPM < 470
	self._nfpRotorAcc = self._nfpRotorAcc and (self._nfpRotorAcc + self.RotorRPM * nfpFrametime * (nfpPhysRot and 4 or 1)) or 0
	local nfpRot = Angle(0,0,self._nfpRotorAcc)
	nfpRot:Normalize()
	self:ManipulateBoneAngles( 9, nfpRot )
	self:SetBodygroup( 1, nfpPhysRot and 0 or 1 )
end

function ENT:NFP_AnimControlSurfaces( nfpFrametime )
	local nfpFT    = nfpFrametime * 10
	local nfpSteer = self:GetSteer()

	local nfpPitch = -nfpSteer.y * 30
	local nfpYaw   = -nfpSteer.z * 20
	local nfpRoll  = math.Clamp( -nfpSteer.x * 60, -30, 30 )

	self._nfpSmPitch = self._nfpSmPitch and self._nfpSmPitch + (nfpPitch - self._nfpSmPitch) * nfpFT or 0
	self._nfpSmYaw   = self._nfpSmYaw   and self._nfpSmYaw   + (nfpYaw   - self._nfpSmYaw)   * nfpFT or 0
	self._nfpSmRoll  = self._nfpSmRoll  and self._nfpSmRoll  + (nfpRoll  - self._nfpSmRoll)  * nfpFT or 0

	self:ManipulateBoneAngles( 3, Angle( 0,  self._nfpSmRoll,  0 ) )
	self:ManipulateBoneAngles( 4, Angle( 0, -self._nfpSmRoll,  0 ) )
	self:ManipulateBoneAngles( 6, Angle( 0, -self._nfpSmPitch, 0 ) )
	self:ManipulateBoneAngles( 5, Angle( self._nfpSmYaw, 0, 0 ) )
end

function ENT:NFP_AnimLandingGear( nfpFrametime )
	self._nfpSmGear = self._nfpSmGear and self._nfpSmGear + (30 * (1 - self:GetLandingGear()) - self._nfpSmGear) * nfpFrametime * 8 or 0
	self:ManipulateBoneAngles( 1, Angle( 0, 30 - self._nfpSmGear, 0 ) )
	self:ManipulateBoneAngles( 2, Angle( 0, 30 - self._nfpSmGear, 0 ) )
end
