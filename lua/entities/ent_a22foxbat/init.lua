AddCSLuaFile( "cl_init.lua" )
AddCSLuaFile( "shared.lua" )
include( "shared.lua" )

-- ============================================================
-- TUNING
-- ============================================================

ENT.NFP_CruiseSpeed      = 280     -- HU/s flat cruise
ENT.NFP_SkyHeightAdd     = 2500    -- HU above ground at spawn
ENT.NFP_AltMin           = 1800    -- min altitude above ground
ENT.NFP_AltMax           = 3800    -- max altitude above ground
ENT.NFP_AltStepRate      = 35      -- HU/s vertical climb/dive rate during cruise
ENT.NFP_TurnRate         = 28      -- degrees/s yaw turn rate during cruise
ENT.NFP_WanderInterval   = { 6, 14 }  -- seconds between new wander targets
ENT.NFP_WanderRadius     = 3000    -- HU radius around center to pick wander targets
ENT.NFP_BankMax          = 22      -- max visual bank angle degrees
ENT.NFP_PitchCruise      = -3      -- nose-up tilt during level cruise

ENT.NFP_DiveSpeed        = 1800    -- HU/s max dive speed
ENT.NFP_DiveAccel        = 0.022   -- lerp factor for dive speed ramp
ENT.NFP_DiveTrackRate    = 0.08    -- seconds between target re-acquisition
ENT.NFP_WobbleAmpH       = 160     -- horizontal wobble amplitude HU
ENT.NFP_WobbleAmpV       = 110     -- vertical wobble amplitude HU
ENT.NFP_WobbleSpeedH     = 4.2     -- horizontal wobble frequency
ENT.NFP_WobbleSpeedV     = 3.0     -- vertical wobble frequency

ENT.NFP_SearchWindow     = 12      -- seconds in dive_search before returning to cruise
ENT.NFP_CruiseDiveChance = 0.35    -- chance per wander tick to arm dive_search

local NFP_BELLY_BOMB_OFFSET = Vector( 15, 0, -35 )

-- ============================================================
-- SOUNDS
-- ============================================================

local NFP_SND_START = "lvs_darklord/mi_engine/mi24_engine_start_exterior.wav"
local NFP_SND_LOOP  = "^lvs_darklord/rotors/rotor_loop_close.wav"
local NFP_SND_DIST  = "^lvs_darklord/rotors/rotor_loop_dist.wav"
local NFP_SND_PASS  = {
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
        self:NFP_Debug( "WARNING: gb_bomb_sc250 not available" )
        return
    end

    nfpBomb.IsOnPlane      = true
    nfpBomb.FoxbatAttached = true
    nfpBomb:SetPos( nfpWorldPos )
    nfpBomb:SetAngles( self:GetAngles() )
    nfpBomb:Spawn()
    nfpBomb:Activate()
    nfpBomb:Arm()
    nfpBomb:SetCollisionGroup( COLLISION_GROUP_DEBRIS_TRIGGER )

    nfpBomb.OnTakeDamage = function( nfpSelf, dmginfo )
        if nfpSelf.FoxbatAttached then return end
        return nfpSelf.BaseClass.OnTakeDamage( nfpSelf, dmginfo )
    end

    self._nfpBellyBomb     = nfpBomb
    self._nfpBellyBombWeld = constraint.Weld( self, nfpBomb, 0, 0, 0, true, true )
    self._nfpBombDetached  = false

    self:NFP_Debug( "Belly bomb armed" )
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
        if IsValid( nfpBomb ) then nfpBomb:ExplodeCorrectly() end
    end )
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
    self._nfpCenterPos    = self:GetVar( "CenterPos",            self:GetPos() )
    self._nfpCallDir      = self:GetVar( "CallDir",              Vector(1,0,0) )
    self._nfpLifetime     = self:GetVar( "Lifetime",             40 )
    self._nfpCruiseSpeed  = self:GetVar( "Speed",                self.NFP_CruiseSpeed )
    self._nfpOrbitRadius  = self:GetVar( "OrbitRadius",          self.NFP_WanderRadius )
    self._nfpSkyHeightAdd = self:GetVar( "SkyHeightAdd",         self.NFP_SkyHeightAdd )
    self._nfpDiveExpDmg   = self:GetVar( "DIVE_ExplosionDamage", 350 )
    self._nfpDiveExpRad   = self:GetVar( "DIVE_ExplosionRadius", 600 )

    -- Sanitize call direction
    if self._nfpCallDir:LengthSqr() <= 1 then self._nfpCallDir = Vector(1,0,0) end
    self._nfpCallDir.z = 0
    self._nfpCallDir:Normalize()

    -- Find ground
    local nfpGround = self:NFP_FindGround( self._nfpCenterPos )
    if nfpGround == -1 then self:NFP_Debug( "FindGround failed" ) self:Remove() return end

    self._nfpGroundZ = nfpGround
    self._nfpDieTime = CurTime() + self._nfpLifetime

    -- Spawn position behind call direction
    local nfpSpawnPos = self._nfpCenterPos - self._nfpCallDir * 2000
    nfpSpawnPos = Vector( nfpSpawnPos.x, nfpSpawnPos.y, nfpGround + self._nfpSkyHeightAdd )
    if not util.IsInWorld( nfpSpawnPos ) then
        nfpSpawnPos = Vector( self._nfpCenterPos.x, self._nfpCenterPos.y, nfpGround + self._nfpSkyHeightAdd )
    end
    if not util.IsInWorld( nfpSpawnPos ) then
        self:NFP_Debug( "Spawn out of world" ) self:Remove() return
    end

    -- Model & physics
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

    -- Angles
    local nfpStartYaw = self._nfpCallDir:Angle().y + 70
    self:SetAngles( Angle( self.NFP_PitchCruise, nfpStartYaw, 0 ) )

    -- Flight state
    self._nfpYaw          = nfpStartYaw
    self._nfpTargetYaw    = nfpStartYaw
    self._nfpVisualBank   = 0
    self._nfpAltCurrent   = nfpSpawnPos.z
    self._nfpAltTarget    = nfpSpawnPos.z
    self._nfpJitterPhase  = math.Rand( 0, math.pi * 2 )

    -- Wander
    self._nfpWanderTarget    = nfpSpawnPos  -- XY wander goal
    self._nfpNextWander      = CurTime() + math.Rand( 3, 7 )

    -- Mode: "cruise", "dive_search", "dive_commit"
    self._nfpMode            = "cruise"

    -- Dive
    self._nfpDiveActive      = false
    self._nfpDiveExploded    = false
    self._nfpDiveTarget      = nil
    self._nfpDiveTargetPos   = nil
    self._nfpDiveNextTrack   = 0
    self._nfpDiveCommitTime  = 0
    self._nfpDiveSpeedNow    = self.NFP_DiveSpeed * 0.5
    self._nfpWobblePhaseH    = 0
    self._nfpWobblePhaseV    = math.Rand( 0, math.pi * 2 )
    self._nfpDiveAimOffset   = Vector(0,0,0)

    -- Search
    self._nfpSearchExpiry    = 0

    -- Physics
    self._nfpPhysObj = self:GetPhysicsObject()
    if IsValid( self._nfpPhysObj ) then
        self._nfpPhysObj:Wake()
        self._nfpPhysObj:EnableGravity( false )
        self._nfpPhysObj:SetDamping( 0, 0 )
    end

    -- Sounds
    sound.Play( NFP_SND_START, nfpSpawnPos, 90, 100, 1.0 )

    self._nfpSndClose = CreateSound( self, NFP_SND_LOOP )
    if self._nfpSndClose then
        self._nfpSndClose:SetSoundLevel( 125 )
        self._nfpSndClose:ChangePitch( 100, 0 )
        self._nfpSndClose:ChangeVolume( 1.0, 0.5 )
        self._nfpSndClose:Play()
    end

    self._nfpSndDist = CreateSound( self, NFP_SND_DIST )
    if self._nfpSndDist then
        self._nfpSndDist:SetSoundLevel( 125 )
        self._nfpSndDist:ChangePitch( 100, 0 )
        self._nfpSndDist:ChangeVolume( 1.0, 0.5 )
        self._nfpSndDist:Play()
    end

    self._nfpNextPassSnd = CurTime() + math.Rand( 5, 10 )

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
        self:NFP_DiveExplode( self:GetPos() )
    end
end

-- ============================================================
-- THINK — master dispatcher
-- ============================================================

function ENT:Think()
    local nfpNow = CurTime()
    local nfpDT  = FrameTime()

    if nfpNow >= self._nfpDieTime then self:Remove() return end

    -- Keep physics awake
    if IsValid( self._nfpPhysObj ) and self._nfpPhysObj:IsAsleep() then
        self._nfpPhysObj:Wake()
    end

    -- Pass-by sound
    if nfpNow >= self._nfpNextPassSnd then
        sound.Play( table.Random( NFP_SND_PASS ), self:GetPos(), 100, math.random(96,104), 1.0 )
        self._nfpNextPassSnd = nfpNow + math.Rand( 6, 14 )
    end

    if self._nfpMode == "cruise" then
        self:NFP_ThinkCruise( nfpNow, nfpDT )
    elseif self._nfpMode == "dive_search" then
        self:NFP_ThinkDiveSearch( nfpNow, nfpDT )
    elseif self._nfpMode == "dive_commit" then
        self:NFP_ThinkDiveCommit( nfpNow, nfpDT )
    end

    self:NextThink( nfpNow )
    return true
end

-- ============================================================
-- CRUISE THINK — wander + altitude drift + turn toward waypoints
-- ============================================================

function ENT:NFP_ThinkCruise( nfpNow, nfpDT )
    local nfpPos = self:GetPos()

    -- ── Pick new wander target ──────────────────────────────
    if nfpNow >= self._nfpNextWander then
        -- Random point within wander radius of center
        local nfpAngle  = math.Rand( 0, 360 )
        local nfpDist   = math.Rand( self._nfpOrbitRadius * 0.3, self._nfpOrbitRadius )
        local nfpWX     = self._nfpCenterPos.x + math.cos( math.rad(nfpAngle) ) * nfpDist
        local nfpWY     = self._nfpCenterPos.y + math.sin( math.rad(nfpAngle) ) * nfpDist

        -- New altitude target within allowed band
        local nfpAltLow  = self._nfpGroundZ + self.NFP_AltMin
        local nfpAltHigh = self._nfpGroundZ + self.NFP_AltMax
        self._nfpAltTarget = math.Rand( nfpAltLow, nfpAltHigh )

        self._nfpWanderTarget = Vector( nfpWX, nfpWY, self._nfpAltTarget )
        self._nfpNextWander   = nfpNow + math.Rand( self.NFP_WanderInterval[1], self.NFP_WanderInterval[2] )

        -- Roll chance to arm dive_search next wander tick
        if math.random() < self.NFP_CruiseDiveChance then
            self._nfpMode = "dive_search"
            self._nfpSearchExpiry = nfpNow + self.NFP_SearchWindow
            self:NFP_Debug( "DIVE_SEARCH armed" )
            return
        end

        self:NFP_Debug( "New wander: " .. tostring(self._nfpWanderTarget) )
    end

    -- ── Steer toward wander target ──────────────────────────
    local nfpToTarget = self._nfpWanderTarget - nfpPos
    local nfpDesiredYaw = math.deg( math.atan2( nfpToTarget.y, nfpToTarget.x ) )

    -- Shortest-path yaw error
    local nfpYawErr = math.NormalizeAngle( nfpDesiredYaw - self._nfpYaw )

    -- Clamp turn per frame
    local nfpTurnStep = math.Clamp( nfpYawErr, -self.NFP_TurnRate * nfpDT, self.NFP_TurnRate * nfpDT )
    self._nfpYaw = self._nfpYaw + nfpTurnStep

    -- ── Altitude step toward target ─────────────────────────
    local nfpAltErr   = self._nfpAltTarget - self._nfpAltCurrent
    local nfpAltStep  = math.Clamp( nfpAltErr, -self.NFP_AltStepRate * nfpDT, self.NFP_AltStepRate * nfpDT )
    self._nfpAltCurrent = self._nfpAltCurrent + nfpAltStep

    -- Visual pitch: nose up climbing, nose down descending
    local nfpVisualPitch = math.Clamp( -nfpAltStep / (self.NFP_AltStepRate * nfpDT) * 12 + self.NFP_PitchCruise, -20, 15 )

    -- ── Jitter ──────────────────────────────────────────────
    self._nfpJitterPhase = self._nfpJitterPhase + nfpDT * 1.3
    local nfpJitter      = math.sin( self._nfpJitterPhase ) * 8

    -- ── Bank into turn ──────────────────────────────────────
    local nfpTargetBank = math.Clamp( -nfpYawErr * 0.6, -self.NFP_BankMax, self.NFP_BankMax )
    self._nfpVisualBank = self._nfpVisualBank + (nfpTargetBank - self._nfpVisualBank) * math.min( nfpDT * 3, 1 )

    -- ── Move ────────────────────────────────────────────────
    local nfpFwdDir = Angle( 0, self._nfpYaw, 0 ):Forward()
    local nfpNewPos = nfpPos + nfpFwdDir * self._nfpCruiseSpeed * nfpDT
    nfpNewPos.z = self._nfpAltCurrent + nfpJitter

    -- Wall/sky avoidance: if something is close ahead, force a turn
    local nfpTr = util.TraceLine({
        start  = nfpPos,
        endpos = nfpPos + nfpFwdDir * 1200,
        filter = self,
        mask   = MASK_SOLID_BRUSHONLY,
    })
    if nfpTr.Hit then
        self._nfpYaw       = self._nfpYaw + 35 * nfpDT * 60  -- sharp emergency turn
        self._nfpNextWander = nfpNow  -- force new wander target immediately
    end

    self:SetPos( nfpNewPos )
    self:SetAngles( Angle( nfpVisualPitch, self._nfpYaw, self._nfpVisualBank ) )

    if IsValid( self._nfpPhysObj ) then
        self._nfpPhysObj:SetPos( nfpNewPos )
        self._nfpPhysObj:SetVelocity( nfpFwdDir * self._nfpCruiseSpeed )
    end

    if not self:IsInWorld() then self:Remove() end
end

-- ============================================================
-- DIVE_SEARCH — scan for player in forward hemisphere
-- ============================================================

function ENT:NFP_ThinkDiveSearch( nfpNow, nfpDT )
    -- Keep flying during search
    self:NFP_ThinkCruise( nfpNow, nfpDT )

    -- Timeout
    if nfpNow >= self._nfpSearchExpiry then
        self._nfpMode = "cruise"
        self:NFP_Debug( "DIVE_SEARCH expired — back to cruise" )
        return
    end

    local nfpMyPos = self:GetPos()
    local nfpFwd   = self:GetForward()

    for _, nfpPly in ipairs( player.GetAll() ) do
        if not IsValid( nfpPly ) or not nfpPly:Alive() then continue end
        if nfpPly:IsFlagSet( FL_NOTARGET ) then continue end

        local nfpDir = (nfpPly:GetPos() - nfpMyPos):GetNormalized()
        if nfpFwd:Dot( nfpDir ) <= 0 then continue end  -- behind us

        local nfpTr = util.TraceLine({
            start  = nfpMyPos,
            endpos = nfpPly:GetPos(),
            filter = self,
            mask   = MASK_SOLID_BRUSHONLY,
        })
        if nfpTr.Hit then continue end

        -- Commit
        self._nfpMode           = "dive_commit"
        self._nfpDiveTarget     = nfpPly
        self._nfpDiveActive     = false
        self._nfpDiveCommitTime = nfpNow + 0.8
        self:NFP_Debug( "DIVE_COMMIT — locking: " .. nfpPly:GetName() )
        return
    end
end

-- ============================================================
-- DIVE_COMMIT — telegraph nose-down then full dive
-- ============================================================

function ENT:NFP_ThinkDiveCommit( nfpNow, nfpDT )
    if self._nfpDiveExploded then return end

    -- Telegraph: tilt nose down
    if nfpNow < self._nfpDiveCommitTime then
        local nfpFrac = math.Clamp( (nfpNow - (self._nfpDiveCommitTime - 0.8)) / 0.8, 0, 1 )
        self:SetAngles( Angle( nfpFrac * -55, self._nfpYaw, self._nfpVisualBank ) )
        return
    end

    -- Lost target
    if not IsValid( self._nfpDiveTarget ) or not self._nfpDiveTarget:Alive() then
        self._nfpMode       = "cruise"
        self._nfpDiveActive = false
        self:NFP_Debug( "DIVE_COMMIT: target lost" )
        return
    end

    -- Init dive on first frame
    if not self._nfpDiveActive then
        self._nfpDiveActive      = true
        self._nfpDiveTargetPos   = self._nfpDiveTarget:GetPos()
        self._nfpDiveNextTrack   = nfpNow
        self._nfpDiveExploded    = false
        self._nfpDiveSpeedNow    = self.NFP_DiveSpeed * 0.5
        self._nfpWobblePhaseH    = 0
        self._nfpWobblePhaseV    = math.Rand( 0, math.pi * 2 )
        self._nfpDiveAimOffset   = Vector( math.Rand(-350,350), math.Rand(-350,350), 0 )

        self:SetCollisionGroup( COLLISION_GROUP_NONE )
        if IsValid( self._nfpBellyBomb ) then
            self._nfpBellyBomb:SetCollisionGroup( COLLISION_GROUP_NONE )
        end
        if IsValid( self._nfpPhysObj ) then
            self._nfpPhysObj:EnableGravity( false )
            self._nfpPhysObj:SetVelocity( Vector(0,0,0) )
        end
        self:SetNWBool( "NFP_Diving", true )
    end

    self:NFP_UpdateDive( nfpNow, nfpDT )
end

-- ============================================================
-- DIVE UPDATE
-- ============================================================

function ENT:NFP_UpdateDive( nfpNow, nfpDT )
    -- Re-acquire target
    if nfpNow >= self._nfpDiveNextTrack then
        if IsValid( self._nfpDiveTarget ) and self._nfpDiveTarget:Alive() then
            self._nfpDiveTargetPos = self._nfpDiveTarget:GetPos() + Vector( math.Rand(-80,80), math.Rand(-80,80), 0 )
        end
        self._nfpDiveNextTrack = nfpNow + self.NFP_DiveTrackRate
    end

    if not self._nfpDiveTargetPos then self:Remove() return end

    local nfpMyPos  = self:GetPos()
    local nfpAimPos = self._nfpDiveTargetPos + self._nfpDiveAimOffset
    local nfpDir    = nfpAimPos - nfpMyPos
    local nfpDist   = nfpDir:Length()

    if nfpDist < 120 then
        self:NFP_DiveExplode( nfpMyPos )
        return
    end

    nfpDir:Normalize()

    -- Speed ramp
    self._nfpDiveSpeedNow = Lerp( self.NFP_DiveAccel, self._nfpDiveSpeedNow, self.NFP_DiveSpeed )

    -- Wobble
    self._nfpWobblePhaseH = self._nfpWobblePhaseH + self.NFP_WobbleSpeedH * nfpDT
    self._nfpWobblePhaseV = self._nfpWobblePhaseV + self.NFP_WobbleSpeedV * nfpDT

    local nfpRight  = Vector( -nfpDir.y, nfpDir.x, 0 )
    if nfpRight:LengthSqr() < 0.01 then nfpRight = Vector(1,0,0) end
    nfpRight:Normalize()

    local nfpUpPerp = Vector(0,0,1) - nfpDir * nfpDir:Dot( Vector(0,0,1) )
    if nfpUpPerp:LengthSqr() < 0.01 then nfpUpPerp = Vector(0,1,0) end
    nfpUpPerp:Normalize()

    local nfpWobbleScale = math.Clamp( nfpDist / 350, 0, 1 )
    local nfpWobble =
        nfpRight  * math.sin( self._nfpWobblePhaseH ) * self.NFP_WobbleAmpH * nfpWobbleScale +
        nfpUpPerp * math.sin( self._nfpWobblePhaseV ) * self.NFP_WobbleAmpV * nfpWobbleScale

    local nfpNewPos = nfpMyPos + nfpDir * self._nfpDiveSpeedNow * nfpDT + nfpWobble * nfpDT

    -- Face travel direction
    local nfpTravelDir = nfpNewPos - nfpMyPos
    if nfpTravelDir:LengthSqr() > 0.01 then
        local nfpFaceAng = nfpTravelDir:GetNormalized():Angle()
        nfpFaceAng.r = 0
        self:SetAngles( nfpFaceAng )
        self._nfpYaw = nfpFaceAng.y
    end

    -- Geometry hit
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
-- DIVE EXPLODE
-- ============================================================

function ENT:NFP_DiveExplode( nfpPos )
    if self._nfpDiveExploded then return end
    self._nfpDiveExploded = true

    local nfpEd = EffectData()
    nfpEd:SetOrigin( nfpPos ) nfpEd:SetScale(5) nfpEd:SetMagnitude(5) nfpEd:SetRadius(500)
    util.Effect( "HelicopterMegaBomb", nfpEd, true, true )

    local nfpEd2 = EffectData()
    nfpEd2:SetOrigin( nfpPos ) nfpEd2:SetScale(4) nfpEd2:SetMagnitude(4) nfpEd2:SetRadius(400)
    util.Effect( "500lb_air", nfpEd2, true, true )

    sound.Play( "weapon_AWP.Single",               nfpPos, 145, 60, 1.0 )
    sound.Play( "ambient/explosions/explode_8.wav", nfpPos, 140, 90, 1.0 )

    util.BlastDamage( self, self, nfpPos, self._nfpDiveExpRad, self._nfpDiveExpDmg )

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
