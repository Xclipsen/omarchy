local home = os.getenv("HOME") or ""
local newest_first_dirs = {
  [home .. "/Downloads"] = true,
  [home .. "/Pictures"] = true,
  [home .. "/Videos/replay"] = true,
}
local saved_prefs = {}

local function sort_args(pref)
  return {
    pref.sort_by,
    reverse = pref.sort_reverse and "yes" or "no",
    dir_first = pref.sort_dir_first and "yes" or "no",
    translit = pref.sort_translit and "yes" or "no",
  }
end

local function apply_newest_first_sort()
  if not cx or not cx.active or not cx.active.current then
    return
  end

  local tab = cx.tabs.idx
  local cwd = tostring(cx.active.current.cwd)
  local pref = cx.active.pref

  if newest_first_dirs[cwd] then
    if not saved_prefs[tab] then
      saved_prefs[tab] = {
        sort_by = pref.sort_by,
        sort_reverse = pref.sort_reverse,
        sort_dir_first = pref.sort_dir_first,
        sort_translit = pref.sort_translit,
      }
    end
    ya.emit("sort", { "mtime", reverse = "yes", dir_first = "no" })
  elseif saved_prefs[tab] then
    ya.emit("sort", sort_args(saved_prefs[tab]))
    saved_prefs[tab] = nil
  end
end

ps.sub("cd", apply_newest_first_sort)
apply_newest_first_sort()
