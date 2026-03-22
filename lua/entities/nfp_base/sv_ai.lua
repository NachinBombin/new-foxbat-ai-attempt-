-- NFP (NachinFighterPlane) Base AI
-- Standalone replacement for lvs_base sv_ai.lua

function ENT:RunAI()
end

function ENT:AutoAI()
	if not IsValid( self._nfpOwnerEnt ) then return end

	if self._nfpOwnerEnt:InVehicle() then
		if self._nfpOwnerEnt:IsAdmin() then
			self:SetAI( true )
		end
	end
end

function ENT:OnCreateAI()
end

function ENT:OnRemoveAI()
end

function ENT:OnToggleAI( name, old, new )
	if new == old then return end

	if not self:IsInitialized() then
		timer.Simple( FrameTime(), function()
			if not IsValid( self ) then return end

			self:OnToggleAI( name, old, new )
		end )

		return
	end

	self:SetAIGunners( new )

	if new == true then
		local nfpDriver = self:GetDriver()

		if IsValid( nfpDriver ) then
			nfpDriver:ExitVehicle()
		end

		self:SetActive( true )
		self:OnCreateAI()

		hook.Run( "LVS.UpdateRelationship", self )
	else
		self:SetActive( false )
		self:OnRemoveAI()
	end
end

function ENT:OnAITakeDamage( dmginfo )
end

function ENT:AITargetInFront( ent, nfpRange )
	if not IsValid( ent ) then return false end

	if not nfpRange then nfpRange = 45 end

	if nfpRange >= 180 then return true end

	local nfpDirToTarget = (ent:GetPos() - self:GetPos()):GetNormalized()

	local nfpInFront = math.deg( math.acos( math.Clamp( self:GetForward():Dot( nfpDirToTarget ) ,-1,1) ) ) < nfpRange

	return nfpInFront
end

function ENT:AICanSee( nfpOtherEnt )
	if not IsValid( nfpOtherEnt ) then return false end

	local nfpPhysObj = nfpOtherEnt:GetPhysicsObject()

	if IsValid( nfpPhysObj ) then
		local nfpTrace = {
			start = self:LocalToWorld( self:OBBCenter() ),
			endpos = nfpOtherEnt:LocalToWorld( nfpPhysObj:GetMassCenter() ),
			filter = self:GetCrosshairFilterEnts(),
		}

		return util.TraceLine( nfpTrace ).Entity == nfpOtherEnt
	end

	local nfpTrace = {
		start = self:LocalToWorld( self:OBBCenter() ),
		endpos = nfpOtherEnt:LocalToWorld( nfpOtherEnt:OBBCenter() ),
		filter = self:GetCrosshairFilterEnts(),
	}

	return util.TraceLine( nfpTrace ).Entity == nfpOtherEnt
end

function ENT:AIGetTarget( nfpViewcone )
	if (self._nfpNextAICheck or 0) > CurTime() then return self._nfpLastTarget end

	self._nfpNextAICheck = CurTime() + 2

	local nfpMyPos = self:GetPos()
	local nfpMyTeam = self:GetAITEAM()

	if nfpMyTeam == 0 then self._nfpLastTarget = NULL return NULL end

	local nfpClosestTarget = NULL
	local nfpTargetDist = 60000

	if not LVS.IgnorePlayers then
		for _, ply in pairs( player.GetAll() ) do
			if not ply:Alive() then continue end

			if ply:IsFlagSet( FL_NOTARGET ) then continue end

			local nfpDist = (ply:GetPos() - nfpMyPos):Length()

			if nfpDist > nfpTargetDist then continue end

			local nfpVeh = ply:lvsGetVehicle()

			if IsValid( nfpVeh ) then
				if self:AICanSee( nfpVeh ) and nfpVeh ~= self then
					local nfpHisTeam = nfpVeh:GetAITEAM()

					if nfpHisTeam == 0 then continue end

					if self.AISearchCone then
						if not self:AITargetInFront( nfpVeh, self.AISearchCone ) then continue end
					end

					if nfpHisTeam ~= nfpMyTeam or nfpHisTeam == 3 then
						nfpClosestTarget = nfpVeh
						nfpTargetDist = nfpDist
					end
				end
			else
				local nfpHisTeam = ply:lvsGetAITeam()
				if not ply:IsLineOfSightClear( self ) or nfpHisTeam == 0 then continue end

				if self.AISearchCone then
					if not self:AITargetInFront( ply, self.AISearchCone ) then continue end
				end

				if nfpHisTeam ~= nfpMyTeam or nfpHisTeam == 3 then
					nfpClosestTarget = ply
					nfpTargetDist = nfpDist
				end
			end
		end
	end

	if not LVS.IgnoreNPCs then
		for _, npc in pairs( LVS:GetNPCs() ) do
			local nfpHisTeam = LVS:GetNPCRelationship( npc:GetClass() )

			if nfpHisTeam == 0 or (nfpHisTeam == nfpMyTeam and nfpHisTeam ~= 3) then continue end

			local nfpDist = (npc:GetPos() - nfpMyPos):Length()

			if nfpDist > nfpTargetDist or not self:AICanSee( npc ) then continue end

			if self.AISearchCone then
				if not self:AITargetInFront( npc, self.AISearchCone ) then continue end
			end

			nfpClosestTarget = npc
			nfpTargetDist = nfpDist
		end
	end

	for _, veh in pairs( LVS:GetVehicles() ) do
		if veh:IsDestroyed() then continue end

		if veh == self then continue end

		local nfpDist = (veh:GetPos() - nfpMyPos):Length()

		if nfpDist > nfpTargetDist or not self:AITargetInFront( veh, (nfpViewcone or 100) ) then continue end

		local nfpHisTeam = veh:GetAITEAM()

		if nfpHisTeam == 0 then continue end

		if nfpHisTeam == self:GetAITEAM() then
			if nfpHisTeam ~= 3 then continue end
		end

		if self.AISearchCone then
			if not self:AITargetInFront( veh, self.AISearchCone ) then continue end
		end

		if self:AICanSee( veh ) then
			nfpClosestTarget = veh
			nfpTargetDist = nfpDist
		end
	end

	self._nfpLastTarget = nfpClosestTarget

	return nfpClosestTarget
end

function ENT:IsEnemy( ent )
	if not IsValid( ent ) then return false end

	local nfpHisTeam = 0

	if ent:IsNPC() then
		nfpHisTeam = LVS:GetNPCRelationship( ent:GetClass() )
	end

	if ent:IsPlayer() then
		if ent:IsFlagSet( FL_NOTARGET ) then return false end

		local nfpVeh = ent:lvsGetVehicle()
		if IsValid( nfpVeh ) then
			nfpHisTeam = nfpVeh:GetAITEAM()
		else
			nfpHisTeam = ent:lvsGetAITeam()
		end
	end

	if ent.LVS and ent.GetAITEAM then
		nfpHisTeam = ent:GetAITEAM()
	end

	if nfpHisTeam == 0 then return false end

	if nfpHisTeam == 3 then return true end

	return nfpHisTeam ~= self:GetAITEAM()
end
