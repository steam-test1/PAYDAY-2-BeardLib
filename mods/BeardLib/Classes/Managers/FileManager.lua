FileManager = FileManager or BeardLib:CreateManager("file")
Global.fm = Global.fm or {added_files = {}}

function FileManager:init()
	self.const = {h_preprocessSF = "BeardLibPreProcessScriptData", h_postprocessSF = "BeardLibProcessScriptData"}
	self.process_modes = {
		merge = function(a1, a2) return table.merge(a1, a2) end,
		script_merge = function(a1, a2) return table.script_merge(a1, a2) end,
		add = function(a1, a2) return table.add(a1, a2) end,
		replace = ""
	}
	self.modded_files = {}
	self._files_to_load = {}
	self._files_to_unload = {}

	Hooks:Register(FileManager.const.h_preprocessSF)
	Hooks:Register(FileManager.const.h_postprocessSF)
end

function FileManager:Process(ids_ext, ids_path, name_mt)
	local data = {}
	if DB:_has(ids_ext, ids_path) then
        if name_mt ~= nil then
            data = PackageManager:_script_data(ids_ext, ids_path, name_mt)
        else
            data = PackageManager:_script_data(ids_ext, ids_path)
        end
	end

	Hooks:Call(self.const.h_preprocessSF, ids_ext, ids_path, data)
	local k_ext = ids_ext:key()
	local k_path = ids_path:key()

	local mods = self.modded_files[k_ext] and self.modded_files[k_ext][k_path]
	if mods then
		for id, mdata in pairs(mods) do
			local func = mdata.clbk or mdata.use_clbk
			if not func or func() then
				if mdata.mode and not self.process_modes[mdata.mode] then
					BeardLib:Err("The process mode '%s' does not exist! Skipping...", data.mode)
				else
					local to_replace = (not mdata.mode or mdata.mode == "replace")
					if to_replace and #mods > 1 then
						local id = data.id or "unknown"
						if mdata.file then
							BeardLib:Warn("Script Mod with ID: '%s', Path:'%s' may potentially overwrite changes from other mods! Continuing...", id, mdata.file)
						else
							BeardLib:Warn("Script Mod with ID: '%s', Path:'%s.%s' may potentially overwrite changes from other mods! Continuing...", id, k_path, k_ext)
						end
					end
					local new_data = mdata.tbl or FileIO:ReadScriptData(mdata.file, mdata.type)
					if new_data then
                        if ids_ext == Idstring("nav_data") then
                            BeardLib.Utils:RemoveMetas(new_data)
                        elseif (ids_ext == Idstring("continents") or ids_ext == Idstring("mission")) and mdata.type=="custom_xml" then
                            BeardLib.Utils:RemoveAllNumberIndexes(new_data, true)
                        end

						if to_replace then
							data = new_data
						else
							FileManager.process_modes[mdata.mode](data, new_data)
						end
					elseif FileIO:Exists(mdata.file) then
						BeardLib:Err("Failed reading file '%s', are you trying to load a file with different format?", mdata.file)
					else
						BeardLib:Err("The file '%s' does not exist!", mdata.file)
					end
				end
			end
		end
	end

	Hooks:Call(self.const.h_postprocessSF, ids_ext, ids_path, data)

	return data
end

local texture_key = "8c5b5ab050e16853"
function FileManager:AddFile(ext, path, file)
	if not DB.create_entry then
		return
	end

	ext = ext:id()
	path = path:id()
	local k_ext = ext:key()
	if BLT.AssetManager then
		BLT.AssetManager:CreateEntry(path, ext, file)
	else
		DB:create_entry(ext, path, file)
	end
    Global.fm.added_files[k_ext] = Global.fm.added_files[k_ext] or {}
	Global.fm.added_files[k_ext][path:key()] = file
	if k_ext == texture_key then
		Application:reload_textures({path})
	end
end

function FileManager:AddFileWithCheck(ext, path, file)
	if FileIO:Exists(file) then
		self:AddFile(ext, path, file)
	else
		BeardLib:Err("File does not exist! %s", tostring(file))
	end
end

function FileManager:RemoveFile(ext, path)
	ext = ext:id()
	path = path:id()
	local k_ext = ext:key()
	local k_path = path:key()
	if Global.fm.added_files[k_ext] and Global.fm.added_files[k_ext][k_path] then
		DB:remove_entry(ext, path)
		Global.fm.added_files[k_ext][k_path] = nil
		if k_ext == texture_key then
			Application:reload_textures({path})
		end
	end
end

function FileManager:ScriptAddFile(path, ext, file, options)
	self:ScriptReplaceFile(path, ext, file, options)
end

function FileManager:ScriptReplaceFile(ext, path, file, options)
    if not FileIO:Exists(file) then
        BeardLib:Err("Failed reading scriptdata at path '%s'!", file)
        return
    end

	options = options or {}
	options.type = options.type or "custom_xml"
	local k_ext = ext:key()
	local k_path = path:key()
	self.modded_files[k_ext] = self.modded_files[k_ext] or {}
	self.modded_files[k_ext][k_path] = self.modded_files[k_ext][k_path] or {}
	table.insert(self.modded_files[k_ext][k_path], table.merge(options, {file = file}))
end

function FileManager:ScriptReplace(ext, path, tbl, options)
    options = options or {}
	local k_ext = ext:key()
	local k_path = path:key()
	self.modded_files[k_ext] = self.modded_files[k_ext] or {}
	self.modded_files[k_ext][k_path] = self.modded_files[k_ext][k_path] or {}
	table.insert(self.modded_files[k_ext][k_path], table.merge(options, {tbl = tbl}))
end

function FileManager:Has(ext, path)
	local k_ext = ext:key()
	return Global.fm.added_files[k_ext] and Global.fm.added_files[k_ext][path:key()]
end

function FileManager:HasScriptMod(ext, path)
	local k_ext = ext:key()
	return self.modded_files[k_ext] and self.modded_files[k_ext][path:key()]
end

function FileManager:_LoadAsset(load)
	local path = load.path
	local ext = load.ext
	if not managers.dyn_resource:has_resource(ext, path, managers.dyn_resource.DYN_RESOURCES_PACKAGE) then
		local k_ext = ext:key()
		local k_path = path:key()
		if load.file_path then
			BeardLib:DevLog("loaded file %s", tostring(load.file_path))
		else
			BeardLib:DevLog("loaded file %s.%s", k_path, k_ext)
		end
		managers.dyn_resource:load(ext, path, managers.dyn_resource.DYN_RESOURCES_PACKAGE)
    end
end

function FileManager:_UnloadAsset(unload)
	local path = unload.path
	local ext = unload.ext
	if managers.dyn_resource:has_resource(ext, path, managers.dyn_resource.DYN_RESOURCES_PACKAGE) then
		local k_ext = ext:key()
		local k_path = path:key()
		if unload.file_path then
			BeardLib:DevLog("unloaded file %s", tostring(unload.file_path))
		else
			BeardLib:DevLog("unloaded file %s.%s", k_path, k_ext)
		end
        managers.dyn_resource:unload(ext, path, managers.dyn_resource.DYN_RESOURCES_PACKAGE)
    end
end

function FileManager:LoadAsset(ids_ext, ids_path, file_path)
	local load = {ext = ids_ext:id(), path = ids_path:id(), file_path = file_path}
	if managers.dyn_resource then
		self:_LoadAsset(load)
	else
        table.insert(self._files_to_load, load)
    end
end

function FileManager:UnloadAsset(ids_ext, ids_path, file_path)
	local unload = {ext = ids_ext:id(), path = ids_path:id(), file_path = file_path}
	if managers.dyn_resource then
		self:_UnloadAsset(unload)
	else
        table.insert(self._files_to_unload, unload)
    end
end

FileManager.UnLoadAsset = FileManager.UnloadAsset

function FileManager:Update(t, dt)
	if not managers.dyn_resource then
		return
	end

	for _, load in pairs(self._files_to_load) do
		self:_LoadAsset(load)
	end

	for _, unload in pairs(self._files_to_unload) do
		self:_LoadAsset(unload)
	end

	self._files_to_load = {}
	self._files_to_unload = {}
end