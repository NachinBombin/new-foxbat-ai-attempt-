-- NFP (NachinFighterPlane) FighterPlane AI
-- Standalone replacement for lvs_base_fighterplane sv_ai.lua

function ENT:OnCreateAI()
	self:StartEngine()
	self.NFP_COL_GROUP_OLD = self:GetCollisionGroup()
	self:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )
end

function ENT:OnRemoveAI()
	self:StopEngine()
	self:SetCollisionGroup( self.NFP_COL_GROUP_OLD or COLLISION_GROUP_NONE )
end

function ENT:RunAI()
	local nfpScanLength = 15000
	local nfpMySpeed    = self:GetVelocity():Length()
	local nfpMinDist    = 600 + nfpMySpeed

	local nfpOrigin      = self:LocalToWorld( self:OBBCenter() )
	local nfpTraceFilter = self:GetCrosshairFilterEnts()

	local nfpRayFL  = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(0,20,0) ):Forward()    * nfpScanLength } )
	local nfpRayFR  = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(0,-20,0) ):Forward()   * nfpScanLength } )
	local nfpRayFL2 = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(25,65,0) ):Forward()   * nfpScanLength } )
	local nfpRayFR2 = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(25,-65,0) ):Forward()  * nfpScanLength } )
	local nfpRayFL3 = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(-25,65,0) ):Forward()  * nfpScanLength } )
	local nfpRayFR3 = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(-25,-65,0) ):Forward() * nfpScanLength } )
	local nfpRayFUp   = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(-20,0,0) ):Forward() * nfpScanLength } )
	local nfpRayFDown = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:LocalToWorldAngles( Angle(20,0,0) ):Forward()  * nfpScanLength } )
	local nfpRayFwd  = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + self:GetForward()          * nfpScanLength } )
	local nfpRayDown = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + Vector(0,0,-nfpScanLength) } )
	local nfpRayUp   = util.TraceLine( { start = nfpOrigin, filter = nfpTraceFilter, endpos = nfpOrigin + Vector(0,0, nfpScanLength) } )

	local nfpAvoidVec  = Vector(0,0,0)
	local nfpMyRadius  = self:BoundingRadius()
	local nfpMyPos     = self:GetPos()
	local nfpMyDir     = self:GetForward()

	for _, v in pairs( LVS:GetVehicles() ) do
		if v == self then continue end
		local nfpTheirRadius = v:BoundingRadius()
		local nfpSub  = (nfpMyPos - v:GetPos())
		local nfpDir  = nfpSub:GetNormalized()
		local nfpDist = nfpSub:Length()
		if nfpDist < (nfpTheirRadius + nfpMyRadius + 200) then
			if math.deg( math.acos( math.Clamp( nfpMyDir:Dot( -nfpDir ) ,-1,1) ) ) < 90 then
				nfpAvoidVec = nfpAvoidVec + nfpDir * (nfpTheirRadius + nfpMyRadius + 500)
			end
		end
	end

	local nfpPFL  = nfpRayFL.HitPos  + nfpRayFL.HitNormal  * nfpMinDist + nfpAvoidVec * 8
	local nfpPFR  = nfpRayFR.HitPos  + nfpRayFR.HitNormal  * nfpMinDist + nfpAvoidVec * 8
	local nfpPFL2 = nfpRayFL2.HitPos + nfpRayFL2.HitNormal * nfpMinDist
	local nfpPFR2 = nfpRayFR2.HitPos + nfpRayFR2.HitNormal * nfpMinDist
	local nfpPFL3 = nfpRayFL3.HitPos + nfpRayFL3.HitNormal * nfpMinDist
	local nfpPFR3 = nfpRayFR3.HitPos + nfpRayFR3.HitNormal * nfpMinDist
	local nfpPFUp   = nfpRayFUp.HitPos   + nfpRayFUp.HitNormal   * nfpMinDist
	local nfpPFDown = nfpRayFDown.HitPos  + nfpRayFDown.HitNormal * nfpMinDist
	local nfpPUp    = nfpRayUp.HitPos    + nfpRayUp.HitNormal    * nfpMinDist
	local nfpPDown  = nfpRayDown.HitPos  + nfpRayDown.HitNormal  * nfpMinDist

	local nfpTargetPos = (nfpPFL + nfpPFR + nfpPFL2 + nfpPFR2 + nfpPFL3 + nfpPFR3 + nfpPFUp + nfpPFDown + nfpPUp + nfpPDown) / 10

	local nfpAltitude = (nfpOrigin - nfpRayDown.HitPos):Length()
	local nfpCeiling  = (nfpOrigin - nfpRayUp.HitPos):Length()
	local nfpWallDist = (nfpOrigin - nfpRayFwd.HitPos):Length()
	local nfpThrottle = math.min( nfpWallDist / nfpMySpeed, 1 )

	self._nfpFireInput = false

	if nfpAltitude < 600 or nfpCeiling < 600 or nfpWallDist < (nfpMinDist * 3 * (math.deg( math.acos( math.Clamp( Vector(0,0,1):Dot( nfpMyDir ) ,-1,1) ) ) / 180) ^ 2) then
		if nfpCeiling < 600 then
			nfpThrottle = 0
		else
			nfpThrottle = 1
			if self:HitGround() then
				nfpTargetPos.z = nfpOrigin.z + 750
			else
				if self:GetStability() < 0.5 then
					nfpTargetPos.z = nfpOrigin.z + 1500
				end
			end
		end
	else
		if self:GetStability() < 0.5 then
			nfpTargetPos.z = nfpOrigin.z + 600
		else
			if IsValid( self:GetHardLockTarget() ) then
				nfpTargetPos = self:GetHardLockTarget():GetPos() + nfpAvoidVec * 8
			else
				if nfpAltitude > nfpMySpeed then
					local nfpCurTarget = self._nfpLastCombatTarget

					if not IsValid( self._nfpLastCombatTarget ) or not self:AITargetInFront( self._nfpLastCombatTarget, 135 ) or not self:AICanSee( self._nfpLastCombatTarget ) then
						nfpCurTarget = self:AIGetTarget()
					end

					-- FIX 3: persist the resolved target for next tick
					self._nfpLastCombatTarget = nfpCurTarget

					if IsValid( nfpCurTarget ) then
						if self:AITargetInFront( nfpCurTarget, 65 ) then
							local nfpT = CurTime() + self:EntIndex() * 1337
							nfpTargetPos = nfpCurTarget:GetPos() + nfpAvoidVec * 8 + Vector(0,0, math.sin( nfpT * 5 ) * 500 ) + nfpCurTarget:GetVelocity() * math.abs( math.cos( nfpT * 13.37 ) ) * 5
							nfpThrottle  = math.min( (nfpOrigin - nfpTargetPos):Length() / nfpMySpeed, 1 )

							local nfpHullTrace = util.TraceHull( {
								start  = nfpOrigin,
								endpos = (nfpOrigin + self:GetForward() * 50000),
								mins   = Vector( -50, -50, -50 ),
								maxs   = Vector(  50,  50,  50 ),
								filter = nfpTraceFilter
							} )

							-- FIX 4: removed "or true" — friendly-fire check now actually works
							local nfpCanShoot = (IsValid( nfpHullTrace.Entity ) and nfpHullTrace.Entity.LVS and nfpHullTrace.Entity.GetAITEAM) and (nfpHullTrace.Entity:GetAITEAM() ~= self:GetAITEAM() or nfpHullTrace.Entity:GetAITEAM() == 0)

							if nfpCanShoot and self:AITargetInFront( nfpCurTarget, 22 ) then
								local nfpCurHeat   = self:GetNWHeat()
								local nfpCurWeapon = self:GetSelectedWeapon()

								if nfpCurWeapon > 2 then
									self:NFPSelectWeapon( 1 )
								else
									if nfpCurHeat > 0.9 then
										if nfpCurWeapon == 1 and self:AIHasWeapon( 2 ) then
											self:NFPSelectWeapon( 2 )
										elseif nfpCurWeapon == 2 then
											self:NFPSelectWeapon( 1 )
										end
									else
										if nfpCurHeat == 0 and math.cos( nfpT ) > 0 then
											self:NFPSelectWeapon( 1 )
										end
									end
								end
								self._nfpFireInput = true
							end
						else
							self:NFPSelectWeapon( 1 )
							if nfpAltitude > 6000 and self:AITargetInFront( nfpCurTarget, 90 ) then
								nfpTargetPos = nfpCurTarget:GetPos()
							end
						end
					end
				else
					nfpTargetPos.z = nfpOrigin.z + 2000
				end
			end
		end
		self:RaiseLandingGear()
	end

	self:SetThrottle( nfpThrottle )

	self._nfpSmoothedTarget = self._nfpSmoothedTarget and self._nfpSmoothedTarget + (nfpTargetPos - self._nfpSmoothedTarget) * FrameTime() or self:GetPos()

	-- _nfpAITargetAng: consumed by CalcAero() in init.lua
	self._nfpAITargetAng = (self._nfpSmoothedTarget - self:GetPos()):GetNormalized():Angle()
end

function ENT:NFPSelectWeapon( nfpID )
	if nfpID == self:GetSelectedWeapon() then return end
	local nfpNow = CurTime()
	if (self._nfpNextWeaponSwitch or 0) > nfpNow then return end
	self._nfpNextWeaponSwitch = nfpNow + math.random(3,6)
	self:SelectWeapon( nfpID )
end

function ENT:OnAITakeDamage( dmginfo )
	local nfpAttacker = dmginfo:GetAttacker()
	if not IsValid( nfpAttacker ) then return end
	if not self:AITargetInFront( nfpAttacker, IsValid( self:AIGetTarget() ) and 120 or 45 ) then
		self:SetHardLockTarget( nfpAttacker )
	end
end

function ENT:SetHardLockTarget( nfpTarget )
	self._nfpHardLockTarget = nfpTarget
	self._nfpHardLockExpiry = CurTime() + 4
end

function ENT:GetHardLockTarget()
	if (self._nfpHardLockExpiry or 0) < CurTime() then return NULL end
	return self._nfpHardLockTarget
end
