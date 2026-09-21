-- Podmarchy: runs inside mpv. Mirrors playback into status.json once a second
-- for the shell, and records how far into the episode you are in
-- progress.json, so the next play resumes there.

local mp = require("mp")
local utils = require("mp.utils")

local status_path = os.getenv("PODMARCHY_STATUS_FILE")
local meta_path = os.getenv("PODMARCHY_META_FILE")
local progress_path = os.getenv("PODMARCHY_PROGRESS_FILE")

-- Within this many seconds of the end an episode counts as played.
local DONE_MARGIN = 30
-- Save progress to disk every this many seconds while playing.
local SAVE_EVERY = 10

local function read_json(path)
  if not path or path == "" then return nil end
  local file, err = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  if not text or text == "" then return nil end
  local ok, value = pcall(utils.parse_json, text)
  return ok and value or nil
end

local function write_json(path, value)
  if not path or path == "" then return end
  local ok, text = pcall(utils.format_json, value)
  if not ok or not text then return end
  local tmp = path .. ".tmp"
  local file, err = io.open(tmp, "w")
  if not file then return end
  file:write(text, "\n")
  file:close()
  os.rename(tmp, path)
end

local meta = read_json(meta_path) or {}
local last_pos = 0
local last_dur = 0
local finished = false
local since_save = 0

local function sample()
  local pos = mp.get_property_number("time-pos")
  local dur = mp.get_property_number("duration")
  if pos then last_pos = pos end
  if dur and dur > 0 then last_dur = dur end
end

local function write_status(running)
  sample()
  write_json(status_path, {
    running = running,
    paused = running and mp.get_property_bool("pause", false) or false,
    buffering = running and mp.get_property_bool("paused-for-cache", false) or false,
    position = math.floor(last_pos),
    duration = math.floor(last_dur),
    episode = meta
  })
end

local function save_progress(done)
  if not meta.id or meta.id == "" then return end
  sample()
  if last_dur > 0 and last_pos > last_dur - DONE_MARGIN then done = true end
  -- Nothing heard yet: do not create an entry for an episode barely started.
  if not done and last_pos < 5 then return end

  local all = read_json(progress_path)
  if type(all) ~= "table" then all = {} end
  all[tostring(meta.id)] = {
    position = done and 0 or math.floor(last_pos),
    duration = math.floor(last_dur),
    done = done,
    updated = os.time(),
    feedId = meta.feedId or "",
    title = meta.title or "",
    show = meta.show or "",
    image = meta.image or "",
    url = meta.url or ""
  }
  write_json(progress_path, all)
end

mp.add_periodic_timer(1, function()
  write_status(true)
  if mp.get_property_bool("pause", false) then return end
  since_save = since_save + 1
  if since_save >= SAVE_EVERY then
    since_save = 0
    save_progress(false)
  end
end)

mp.observe_property("pause", "bool", function(_, paused)
  write_status(true)
  if paused then save_progress(false) end
end)

mp.register_event("seek", function() write_status(true) end)

mp.register_event("end-file", function(event)
  if event and event.reason == "eof" then
    finished = true
    save_progress(true)
  end
end)

mp.register_event("shutdown", function()
  if not finished then save_progress(false) end
  write_status(false)
end)

write_status(true)
