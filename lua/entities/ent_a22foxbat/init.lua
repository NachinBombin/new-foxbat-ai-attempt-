AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
-- TUNING
-- ============================================================

ENT.NFP_WeaponWindow     = 8       -- seconds per behavior slot
ENT.NFP_OrbitSpeed       = 250     -- HU/s peaceful cruise
ENT.NFP_OrbitRadius      = 2500    -- HU from center before turning
ENT.NFP_SkyHeightAdd     = 2500    -- HU above ground
ENT.NFP_AltDriftRange    = 700     -- max altitude drift ±HU
ENT.NFP_AltDriftLerp     = 0.003
ENT.NFP_JitterAmplitude  = 12

ENT.NFP_DiveSpeed        = 1800    -- max dive speed HU/s
ENT.NFP_DiveTrackInterval = 0.1
ENT.NFP_SearchConeDeg    = 180     -- cone in degrees for dive trigger

local NFP_BELLY_BOMB_OFFSET = Vector(15, 0, -35)

-- ============================================================
-- SOUNDS
-- ============================================================

local NFP_ENGINE_START = "lvs_darklord/mi_engine/mi24_engine_start_exterior.wav"
local NFP_ENGINE_LOOP  = "^lvs_darklord/rotors/rotor_loop_close.wav"
local NFP_ENGINE_DIST  = "^lvs_darklord/rotors/rotor_loop_dist.wav"
local NFP_PASS_SOUNDS  = {
	"lvs_darklord/rotors/rotor_loop_close.wav",
	"lvs_darklord/rotors/rotor_loop_dist.wav",
}

-- ============================================================
-- BELLY BOMB
-- ============================================================

function ENT:NFP_SpawnBellyBomb()
	local nfpWorldPos = self:LocalToWorld( NFP_BELLY_BOMB_OFFSET )

	local nfpBomb = ents.Create( "gb_bomb_sc250" )
	if not IsValid( nfpBomb ) then
		self:NFP_Debug( "WARNING: could not create gb_bomb_sc250" )
		return
	end

	nfpBomb.IsOnPlane   = true
	nfpBomb:SetPos( nfpWorldPos )
	nfpBomb:SetAngles( self:GetAngles() )
	nfpBomb:Spawn()
	nfpBomb:Activate()
	nfpBomb:Arm()

	nfpBomb:SetCollisionGroup( COLLISION_GROUP_DEBRIS_TRIGGER )

	nfpBomb.FoxbatAttached = true
	nfpBomb.OnTakeDamage = function( bomb_self, dmginfo )
		if bomb_self.FoxbatAttached then return end
		return bomb_self.BaseClass.OnTakeDamage( bomb_self, dmginfo )
	end

	local nfpWeld = constraint.Weld( self, nfpBomb, 0, 0, 0, true, true )

	self._nfpBellyBomb     = nfpBomb
	self._nfpBellyBombWeld = nfpWeld
	self._nfpBombDetached  = false

	self:NFP_Debug( "Belly bomb attached and armed" )
end

function ENT:NFP_DetachBomb( nfpPos )
	if self._nfpBombDetached then return end
	self._nfpBombDetached = true

	local nfpBomb = self._nfpBellyBomb
	if not IsValid( nfpBomb ) then return end

	if IsValid( self._nfpBellyBombWeld ) then
		self._nfpBellyBombWeld:Remove()
		self._nfpBellyBombWeld = nil
	end

	nfpBomb.FoxbatAttached = nil
	nfpBomb:SetCollisionGroup( COLLISION_GROUP_NONE )
	nfpBomb:SetPos( nfpPos )

	timer.Simple( 0, function()
		if not IsValid( nfpBomb ) then return end
		nfpBomb:ExplodeCorrectly()
	end )

	self:NFP_Debug( "Belly bomb detonated at " .. tostring( nfpPos ) )
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:NFP_Debug( nfpMsg )
	print( "[NFP Foxbat] " .. tostring( nfpMsg ) )
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
	self._nfpCenterPos    = self:GetVar( "CenterPos",    self:GetPos() )
	self._nfpCallDir      = self:GetVar( "CallDir",      Vector(1,0,0) )
	self._nfpLifetime     = self:GetVar( "Lifetime",     40 )
	self._nfpOrbitSpeed   = self:GetVar( "Speed",        self.NFP_OrbitSpeed )
	self._nfpOrbitRadius  = self:GetVar( "OrbitRadius",  self.NFP_OrbitRadius )
	self._nfpSkyHeightAdd = self:GetVar( "SkyHeightAdd", self.NFP_SkyHeightAdd )

	self._nfpDiveExpDamage = self:GetVar( "DIVE_ExplosionDamage", 350 )
	self._nfpDiveExpRadius = self:GetVar( "DIVE_ExplosionRadius", 600 )

	if self._nfpCallDir:LengthSqr() <= 1 then self._nfpCallDir = Vector(1,0,0) end
	self._nfpCallDir.z = 0
	self._nfpCallDir:Normalize()

	local nfpGround = self:NFP_FindGround( self._nfpCenterPos )
	if nfpGround == -1 then self:NFP_Debug( "FindGround failed" ) self:Remove() return end

	self._nfpSkyAlt  = nfpGround + self._nfpSkyHeightAdd
	self._nfpDieTime = CurTime() + self._nfpLifetime

	-- Spawn position: approach from behind call direction
	local nfpSpawnPos = self._nfpCenterPos - self._nfpCallDir * 2000
	nfpSpawnPos = Vector( nfpSpawnPos.x, nfpSpawnPos.y, self._nfpSkyAlt )
	if not util.IsInWorld( nfpSpawnPos ) then
		nfpSpawnPos = Vector( self._nfpCenterPos.x, self._nfpCenterPos.y, self._nfpSkyAlt )
	end
	if not util.IsInWorld( nfpSpawnPos ) then
		self:NFP_Debug( "Spawn out of world" ) self:Remove() return
	end

	self:SetModel( "models/blu/cessna.mdl" )
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	self:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )
	self:SetPos( nfpSpawnPos )

	self:SetBodygroup( 4, 1 )
	self:SetBodygroup( 3, 1 )
	self:SetBodygroup( 5, 2 )

	self:SetNWInt( "NFP_HP",    200 )
	self:SetNWInt( "NFP_MaxHP", 200 )

	local nfpStartAng = self._nfpCallDir:Angle()
	self:SetAngles( Angle( 0, nfpStartAng.y + 70, 0 ) )

	-- Flight state
	self._nfpYaw          = self:GetAngles().y
	self._nfpVisualRoll   = 0
	self._nfpVisualPitch  = -4

	-- Altitude drift
	self._nfpAltCurrent  = self._nfpSkyAlt
	self._nfpAltTarget   = self._nfpSkyAlt
	self._nfpAltNextPick = CurTime() + math.Rand( 8, 20 )

	-- Jitter
	self._nfpJitterPhase = math.Rand( 0, math.pi * 2 )

	-- Physics object
	self._nfpPhysObj = self:GetPhysicsObject()
	if IsValid( self._nfpPhysObj ) then
		self._nfpPhysObj:Wake()
		self._nfpPhysObj:EnableGravity( false )
	end

	-- Behavior state machine
	-- Modes: "orbit", "dive_search", "dive_commit"
	self._nfpMode            = "orbit"
	self._nfpBehaviorSlot    = nil
	self._nfpSlotExpiry      = 0
	self._nfpDiveCommitTime  = nil
	self._nfpDivePitch       = 0

	-- Dive tracking
	self._nfpDiveTarget      = nil
	self._nfpDiveTargetPos   = nil
	self._nfpDiveNextTrack   = 0
	self._nfpDiveExploded    = false
	self._nfpDiveAimOffset   = Vector(0,0,0)

	-- Dive wobble
	self._nfpWobblePhase     = 0
	self._nfpWobbleAmp       = 180
	self._nfpWobbleSpeed     = 4.5
	self._nfpWobblePhaseV    = math.Rand( 0, math.pi * 2 )
	self._nfpWobbleAmpV      = 130
	self._nfpWobbleSpeedV    = 3.1

	-- Dive speed
	self._nfpDiveSpeedMin     = self.NFP_DiveSpeed * 0.55
	self._nfpDiveSpeedCurrent = self.NFP_DiveSpeed * 0.55
	self._nfpDiveSpeedLerp    = 0.018

	-- Sounds
	sound.Play( NFP_ENGINE_START, nfpSpawnPos, 90, 100, 1.0 )

	self._nfpSndClose = CreateSound( self, NFP_ENGINE_LOOP )
	if self._nfpSndClose then
		self._nfpSndClose:SetSoundLevel( 125 )
		self._nfpSndClose:ChangePitch( 100, 0 )
		self._nfpSndClose:ChangeVolume( 1.0, 0.5 )
		self._nfpSndClose:Play()
	end

	self._nfpSndDist = CreateSound( self, NFP_ENGINE_DIST )
	if self._nfpSndDist then
		self._nfpSndDist:SetSoundLevel( 125 )
		self._nfpSndDist:ChangePitch( 100, 0 )
		self._nfpSndDist:ChangeVolume( 1.0, 0.5 )
		self._nfpSndDist:Play()
	end

	self._nfpNextPassSound = CurTime() + math.Rand( 5, 10 )

	-- Belly bomb (deferred one frame so entity is fully valid)
	timer.Simple( 0, function()
		if IsValid( self ) then self:NFP_SpawnBellyBomb() end
	end )

	self:NFP_Debug( "Spawned at " .. tostring( nfpSpawnPos ) )
end

-- ============================================================
-- DAMAGE
-- ============================================================

function ENT:OnTakeDamage( dmginfo )
	if self._nfpDiveExploded then return end
	if dmginfo:IsDamageType( DMG_CRUSH ) then return end

	local nfpHP = self:GetNWInt( "NFP_HP", 200 ) - dmginfo:GetDamage()
	self:SetNWInt( "NFP_HP", nfpHP )

	if nfpHP <= 0 then
		self:NFP_Debug( "Shot down!" )
		self:NFP_DiveExplode( self:GetPos() )
	end
end

-- ============================================================
-- THINK — state dispatcher
-- ============================================================

function ENT:Think()
	local nfpNow = CurTime()

	if nfpNow >= self._nfpDieTime then self:Remove() return end

	if not IsValid( self._nfpPhysObj ) then
		self._nfpPhysObj = self:GetPhysicsObject()
	end
	if IsValid( self._nfpPhysObj ) and self._nfpPhysObj:IsAsleep() then
		self._nfpPhysObj:Wake()
	end

	-- Pass-by sound
	if nfpNow >= self._nfpNextPassSound then
		sound.Play( table.Random( NFP_PASS_SOUNDS ), self:GetPos(), 100, math.random(96,104), 1.0 )
		self._nfpNextPassSound = nfpNow + math.Rand( 6, 12 )
	end

	-- State machine
	if self._nfpMode == "orbit" then
		self:NFP_ThinkOrbit( nfpNow )
	elseif self._nfpMode == "dive_search" then
		self:NFP_ThinkDiveSearch( nfpNow )
	elseif self._nfpMode == "dive_commit" then
		self:NFP_ThinkDiveCommit( nfpNow )
	end

	self:NextThink( nfpNow )
	return true
end

-- ============================================================
-- ORBIT THINK — behavior slot randomizer
-- ============================================================

function ENT:NFP_ThinkOrbit( nfpNow )
	-- Pick a new behavior slot when the current one expires
	if not self._nfpBehaviorSlot or nfpNow >= self._nfpSlotExpiry then
		local nfpRoll = math.random( 1, 3 )
		if nfpRoll == 3 then
			self._nfpBehaviorSlot = "dive"
		else
			self._nfpBehaviorSlot = "peaceful"
		end
		self._nfpSlotExpiry = nfpNow + self.NFP_WeaponWindow
		self:NFP_Debug( "Behavior slot: " .. self._nfpBehaviorSlot )
	end

	if self._nfpBehaviorSlot == "dive" then
		-- Arm dive search mode — don't commit yet
		self._nfpMode         = "dive_search"
		self._nfpBehaviorSlot = nil
		self:NFP_Debug( "DIVE_SEARCH armed — scanning 180° cone" )
	end
	-- "peaceful" slot: PhysicsUpdate handles actual flight
end

-- ============================================================
-- DIVE_SEARCH THINK — scan cone, wait for player
-- ============================================================

function ENT:NFP_ThinkDiveSearch( nfpNow )
	-- Safety: if we've been searching too long with no target, go back to orbit
	if not self._nfpSearchExpiry then
		self._nfpSearchExpiry = nfpNow + 15
	end
	if nfpNow >= self._nfpSearchExpiry then
		self._nfpMode         = "orbit"
		self._nfpSearchExpiry = nil
		self:NFP_Debug( "DIVE_SEARCH expired — returning to orbit" )
		return
	end

	-- Scan players in 180° forward cone
	local nfpMyPos = self:GetPos()
	local nfpFwd   = self:GetForward()

	for _, nfpPly in ipairs( player.GetAll() ) do
		if not IsValid( nfpPly ) or not nfpPly:Alive() then continue end
		if nfpPly:IsFlagSet( FL_NOTARGET ) then continue end

		local nfpDir = (nfpPly:GetPos() - nfpMyPos):GetNormalized()
		local nfpDot = nfpFwd:Dot( nfpDir )

		-- 180° cone = dot > 0 (any forward hemisphere)
		if nfpDot <= 0 then continue end

		-- Line of sight check
		local nfpTr = util.TraceLine({
			start  = nfpMyPos,
			endpos = nfpPly:GetPos(),
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if nfpTr.Hit then continue end

		-- Player spotted in cone with LOS — commit to dive
		self._nfpMode         = "dive_commit"
		self._nfpSearchExpiry = nil
		self._nfpDiveTarget   = nfpPly
		self._nfpDiveCommitTime = nfpNow + 1.0  -- 1s nose-down telegraph
		self:NFP_Debug( "DIVE_COMMIT — target spotted: " .. nfpPly:GetName() )
		return
	end
end

-- ============================================================
-- DIVE_COMMIT THINK — telegraph then full dive
-- ============================================================

function ENT:NFP_ThinkDiveCommit( nfpNow )
	if self._nfpDiveExploded then return end

	-- Telegraph: pitch nose down over 1 second
	if nfpNow < self._nfpDiveCommitTime then
		local nfpFrac = math.Clamp( (nfpNow - (self._nfpDiveCommitTime - 1.0)) / 1.0, 0, 1 )
		self._nfpDivePitch = nfpFrac * -60
		self:SetAngles( Angle( self._nfpDivePitch, self._nfpYaw, self._nfpVisualRoll ) )
		return
	end

	-- Validate target still alive
	if not IsValid( self._nfpDiveTarget ) or not self._nfpDiveTarget:Alive() then
		-- Lost target — return to orbit
		self._nfpMode          = "orbit"
		self._nfpDiveTarget    = nil
		self._nfpDiveCommitTime = nil
		self._nfpDivePitch     = 0
		self:NFP_Debug( "DIVE_COMMIT: target lost — returning to orbit" )
		return
	end

	-- First frame of actual dive: initialize tracking
	if not self._nfpDiveActive then
		self._nfpDiveActive      = true
		self._nfpDiveTargetPos   = self._nfpDiveTarget:GetPos()
		self._nfpDiveNextTrack   = nfpNow
		self._nfpDivePitch       = 0
		self._nfpDiveExploded    = false
		self._nfpWobblePhase     = 0
		self._nfpWobblePhaseV    = math.Rand( 0, math.pi * 2 )
		self._nfpDiveSpeedCurrent = self._nfpDiveSpeedMin
		self._nfpDiveAimOffset   = Vector(
			math.Rand( -400, 400 ),
			math.Rand( -400, 400 ),
			0
		)

		-- Switch to no-collision for the dive
		self:SetCollisionGroup( COLLISION_GROUP_NONE )
		self:SetSolid( SOLID_VPHYSICS )

		if IsValid( self._nfpBellyBomb ) then
			self._nfpBellyBomb:SetCollisionGroup( COLLISION_GROUP_NONE )
		end
		if IsValid( self._nfpPhysObj ) then
			self._nfpPhysObj:EnableGravity( false )
			self._nfpPhysObj:SetVelocity( Vector(0,0,0) )
		end

		self:SetNWBool( "NFP_Diving", true )
	end

	self:NFP_UpdateDive( nfpNow )
end

-- ============================================================
-- DIVE UPDATE — called every Think during active dive
-- ============================================================

function ENT:NFP_UpdateDive( nfpNow )
	-- Re-track target position at interval
	if nfpNow >= self._nfpDiveNextTrack then
		if IsValid( self._nfpDiveTarget ) and self._nfpDiveTarget:Alive() then
			local nfpJitter = Vector(
				math.Rand( -120, 120 ),
				math.Rand( -120, 120 ),
				0
			)
			self._nfpDiveTargetPos = self._nfpDiveTarget:GetPos() + nfpJitter
		end
		self._nfpDiveNextTrack = nfpNow + self.NFP_DiveTrackInterval
	end

	if not self._nfpDiveTargetPos then self:Remove() return end

	local nfpAimPos = self._nfpDiveTargetPos + self._nfpDiveAimOffset
	local nfpMyPos  = self:GetPos()
	local nfpDir    = nfpAimPos - nfpMyPos
	local nfpDist   = nfpDir:Length()

	-- Proximity detonation
	if nfpDist < 120 then
		self:NFP_DiveExplode( nfpMyPos )
		return
	end

	nfpDir:Normalize()

	-- Speed ramp up
	self._nfpDiveSpeedCurrent = Lerp( self._nfpDiveSpeedLerp, self._nfpDiveSpeedCurrent, self.NFP_DiveSpeed )

	local nfpDT = FrameTime()

	-- Lateral wobble (horizontal)
	self._nfpWobblePhase = self._nfpWobblePhase + self._nfpWobbleSpeed * nfpDT
	local nfpFlatRight   = Vector( -nfpDir.y, nfpDir.x, 0 )
	if nfpFlatRight:LengthSqr() < 0.01 then nfpFlatRight = Vector(1,0,0) end
	nfpFlatRight:Normalize()

	-- Vertical wobble
	self._nfpWobblePhaseV = self._nfpWobblePhaseV + self._nfpWobbleSpeedV * nfpDT
	local nfpUp    = Vector(0,0,1)
	local nfpUpPerp = nfpUp - nfpDir * nfpDir:Dot(nfpUp)
	if nfpUpPerp:LengthSqr() < 0.01 then nfpUpPerp = Vector(0,1,0) end
	nfpUpPerp:Normalize()

	local nfpWobbleScale = math.Clamp( nfpDist / 400, 0, 1 )

	local nfpWobble =
		nfpFlatRight * math.sin( self._nfpWobblePhase )  * self._nfpWobbleAmp  * nfpWobbleScale +
		nfpUpPerp    * math.sin( self._nfpWobblePhaseV ) * self._nfpWobbleAmpV * nfpWobbleScale

	local nfpStep   = nfpDir * self._nfpDiveSpeedCurrent * nfpDT
	local nfpNewPos = nfpMyPos + nfpStep + nfpWobble * nfpDT

	-- Face travel direction
	local nfpTravelDir = nfpNewPos - nfpMyPos
	if nfpTravelDir:LengthSqr() > 0.01 then
		nfpTravelDir:Normalize()
		local nfpFaceAng = nfpTravelDir:Angle()
		nfpFaceAng.r = 0
		self:SetAngles( nfpFaceAng )
		self._nfpYaw = nfpFaceAng.y
	end

	-- Geometry hit check
	local nfpTr = util.TraceLine({
		start  = nfpMyPos,
		endpos = nfpNewPos,
		filter = self,
		mask   = MASK_SOLID,
	})
	if nfpTr.Hit then
		self:NFP_DiveExplode( nfpTr.HitPos )
		return
	end

	self:SetPos( nfpNewPos )
	if IsValid( self._nfpPhysObj ) then
		self._nfpPhysObj:SetPos( nfpNewPos )
		self._nfpPhysObj:SetVelocity( Vector(0,0,0) )
	end
end

-- ============================================================
-- PHYSICS UPDATE — orbit flight (only runs when not diving)
-- ============================================================

function ENT:PhysicsUpdate( phys )
	if self._nfpMode == "dive_commit" then return end
	if CurTime() >= self._nfpDieTime then self:Remove() return end

	local nfpPos = self:GetPos()
	local nfpNow = CurTime()

	-- Altitude drift
	if nfpNow >= self._nfpAltNextPick then
		self._nfpAltTarget   = self._nfpSkyAlt + math.Rand( -self.NFP_AltDriftRange, self.NFP_AltDriftRange )
		self._nfpAltNextPick = nfpNow + math.Rand( 10, 25 )
	end
	self._nfpAltCurrent = Lerp( self.NFP_AltDriftLerp, self._nfpAltCurrent, self._nfpAltTarget )

	-- Jitter
	self._nfpJitterPhase = self._nfpJitterPhase + 0.04
	local nfpJitter      = math.sin( self._nfpJitterPhase ) * self.NFP_JitterAmplitude

	self:SetPos( Vector( nfpPos.x, nfpPos.y, self._nfpAltCurrent + nfpJitter ) )

	if IsValid( phys ) then
		phys:SetVelocity( self:GetForward() * self._nfpOrbitSpeed )
	end

	-- Orbit turn when outside radius
	local nfpFlat       = Vector( nfpPos.x, nfpPos.y, 0 )
	local nfpFlatCenter = Vector( self._nfpCenterPos.x, self._nfpCenterPos.y, 0 )
	local nfpDist       = nfpFlat:Distance( nfpFlatCenter )

	if nfpDist > self._nfpOrbitRadius and (self._nfpTurnDelay or 0) < nfpNow then
		self._nfpYaw        = self._nfpYaw + 0.1
		self._nfpTurnDelay  = nfpNow + 0.02
		self._nfpVisualRoll = Lerp( 0.05, self._nfpVisualRoll, 8 )
	else
		self._nfpVisualRoll = Lerp( 0.03, self._nfpVisualRoll, 0 )
	end

	-- Sky avoidance
	local nfpTr = util.QuickTrace( self:GetPos(), self:GetForward() * 3000, self )
	if nfpTr.HitSky then
		self._nfpYaw = self._nfpYaw + 0.3
	end

	self:SetAngles( Angle( self._nfpVisualPitch, self._nfpYaw, self._nfpVisualRoll ) )

	if not self:IsInWorld() then
		self:NFP_Debug( "Out of world — removing" )
		self:Remove()
	end
end

-- ============================================================
-- DIVE EXPLODE
-- ============================================================

function ENT:NFP_DiveExplode( nfpPos )
	if self._nfpDiveExploded then return end
	self._nfpDiveExploded = true

	self:NFP_Debug( "Exploding at " .. tostring( nfpPos ) )

	local nfpEd1 = EffectData()
	nfpEd1:SetOrigin( nfpPos ) nfpEd1:SetScale(5) nfpEd1:SetMagnitude(5) nfpEd1:SetRadius(500)
	util.Effect( "HelicopterMegaBomb", nfpEd1, true, true )

	local nfpEd2 = EffectData()
	nfpEd2:SetOrigin( nfpPos ) nfpEd2:SetScale(4) nfpEd2:SetMagnitude(4) nfpEd2:SetRadius(400)
	util.Effect( "500lb_air", nfpEd2, true, true )

	local nfpEd3 = EffectData()
	nfpEd3:SetOrigin( nfpPos + Vector(0,0,60) ) nfpEd3:SetScale(3) nfpEd3:SetMagnitude(3) nfpEd3:SetRadius(300)
	util.Effect( "500lb_air", nfpEd3, true, true )

	sound.Play( "weapon_AWP.Single",               nfpPos, 145, 60,  1.0 )
	sound.Play( "ambient/explosions/explode_8.wav", nfpPos, 140, 90,  1.0 )

	util.BlastDamage( self, self, nfpPos, self._nfpDiveExpRadius, self._nfpDiveExpDamage )

	self:NFP_DetachBomb( nfpPos )
	self:Remove()
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:NFP_FindGround( nfpCenterPos )
	local nfpStart  = Vector( nfpCenterPos.x, nfpCenterPos.y, nfpCenterPos.z + 64 )
	local nfpEnd    = Vector( nfpCenterPos.x, nfpCenterPos.y, -16384 )
	local nfpFilter = { self }
	local nfpIter   = 0

	while nfpIter < 100 do
		local nfpTr = util.TraceLine({ start = nfpStart, endpos = nfpEnd, filter = nfpFilter })
		if nfpTr.HitWorld then return nfpTr.HitPos.z end
		if IsValid( nfpTr.Entity ) then
			table.insert( nfpFilter, nfpTr.Entity )
		else
			break
		end
		nfpIter = nfpIter + 1
	end
	return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
	if self._nfpSndClose then self._nfpSndClose:Stop() end
	if self._nfpSndDist  then self._nfpSndDist:Stop()  end

	if not self._nfpBombDetached and IsValid( self._nfpBellyBomb ) then
		self._nfpBellyBomb:Remove()
	end
end
