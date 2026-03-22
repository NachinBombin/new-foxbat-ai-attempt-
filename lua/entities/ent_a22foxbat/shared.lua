-- A22 Foxbat — entity identity
-- Standalone entity. NOT an LVS vehicle. NOT a base_vehicle.
-- All logic is in init.lua (server) and cl_init.lua (client).

ENT.Type           = "anim"
ENT.Base           = "base_anim"

ENT.PrintName      = "A22 Foxbat"
ENT.Author         = "NachinBombin"
ENT.Information    = "Autonomous loiter munition. Cruises, dives on player contact."
ENT.Category       = "A22 Foxbat"

ENT.Spawnable      = false
ENT.AdminSpawnable = false

ENT.RenderGroup    = RENDERGROUP_OPAQUE
