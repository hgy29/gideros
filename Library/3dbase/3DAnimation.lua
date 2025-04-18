D3Anim={}
--[[ State of animated meshs
- Each animated mesh have a list of bone descriptors (animBones) and a model reference (bonesTop)
]]
D3Anim._animated={} 

-- State of animated models (which can contain several meshes)
-- A mesh's model is given by its 'bonesTop'
D3Anim._animatedModel={} 

function D3Anim.updateBones()
	-- Go through all meshes with dirty models
	local cleaned={}
	local bonesMat={}
	for k,a in pairs(D3Anim._animated) do	
		if k:isVisible() and D3Anim._animatedModel[k.bonesTop].dirty then 
			local bt={}
			local bn=1
			for n,bd in ipairs(k.animBones) do
				local b=bd.bone
				local m
				if b then
					-- Bone to Mesh
					m=bonesMat[b]
					if not m then
						m=k.bonesTop:spriteToLocalMatrix(b)
						m:multiply(b.poseIMat)				
						bonesMat[b]=m
					end
				else
					m=Matrix.new()
				end
			
				bt[bn],bt[bn+1],bt[bn+2],bt[bn+3],
				bt[bn+4],bt[bn+5],bt[bn+6],bt[bn+7],
				bt[bn+8],bt[bn+9],bt[bn+10],bt[bn+11],
				bt[bn+12],bt[bn+13],bt[bn+14],bt[bn+15]=m:getMatrix()
				bn=bn+16
			end
			k:setShaderConstant("bones",Shader.CMATRIX,#k.animBones,bt)
			cleaned[k.bonesTop]=true
		end
		a.dirty=false
	end
	for k,_ in pairs(cleaned) do
		D3Anim._animatedModel[k].dirty=false
	end
end

function D3Anim.animate(m,a)
	local ta={}
	local dtm=(os:timer()-a.tm)*1000*(a.speed or 1)
	local hasNext=false
	for _,b in ipairs(a.anim.bones) do
		local cf=1
		while cf<#b.keyframes and b.keyframes[cf].keytime<dtm do cf+=1 end
		if cf<#b.keyframes then hasNext=true end
		local f=b.keyframes[cf]
		if type(m.bones[b.boneId])=="table" then
			local nf=m.bones[b.boneId]
			local cm={ s=f.scale or nf.srt.s, r=f.rotation or nf.srt.r, t=f.translation or nf.srt.t}
			ta[b.boneId]=cm
		end
	end
	if not hasNext then
		if not a.loop then return ta,true end
		a.tm=os:timer()
	end
	return ta,false
end

function D3Anim.tick()
	-- Animate all models
	for k,a in pairs(D3Anim._animatedModel) do	
		if k:isVisible() then
			local ares={}
			local aend={}
			-- Collect contributions from all running animations on this model
			for slot,anim in pairs(a.animations) do
				local function animateIns(mvs,ratio)
					for bone,srt in pairs(mvs) do
						ares[bone]=ares[bone] or {}
						table.insert(ares[bone],{ratio=ratio,mat={G3DFormat.srtToMatrix(srt):getMatrix()}})
					end
				end
				local ao,al,ac,aor=nil,nil,nil,1
				if anim.oldAnim then
					local aratio=(os:timer()-anim.oldStart)/anim.oldLen
					if aratio>=1 then aratio=1 end
					if aratio<0 then aratio=0 end
					ao,al=D3Anim.animate(k,anim.oldAnim)
					aor=1-aratio
					if al or aratio>=1 then anim.oldAnim=nil end
				end
				ac,al=D3Anim.animate(k,anim)
				if ao and ac then animateIns(ao,aor) animateIns(ac,1-aor)
				elseif ao then animateIns(ao,1)
				elseif ac then animateIns(ac,1)
				else aend[slot]=true
				end
				if al and anim.onEnd then anim.onEnd(slot) end
			end
			for slot,_ in pairs(aend) do 
				a.animations[slot]=nil 
			end
			-- Compute bones matrices
			local rm=Matrix.new() 
			for bone,srtl in pairs(ares) do
				if #srtl>0 then
					local cm={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
					local tsr=0
					for _,srt in ipairs(srtl) do tsr+=srt.ratio end
					for _,srt in ipairs(srtl) do
						local rsc=1/#srtl
						if tsr>0 then rsc=srt.ratio/tsr end
						for k=1,16 do cm[k]+=srt.mat[k]*rsc end
					end
					rm:setMatrix(unpack(cm))
					k.bones[bone]:setMatrix(rm)
				end
			end
			a.dirty=true
		end
	end
	-- Update bones rendering
	D3Anim.updateBones()
end

function D3Anim.setBonesPose(m,poses)
	m=m.bonesTop
	local a=D3Anim._animatedModel[m]
	for bone,srtl in pairs(poses) do
		if #srtl>0 then
			local cm={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
			local tsr=0
			for _,srt in ipairs(srtl) do tsr+=srt.ratio end
			if tsr>0 then
				for _,srt in ipairs(srtl) do
					local rsc=1/#srtl
					if tsr>0 then rsc=srt.ratio/tsr end
					for k=1,16 do cm[k]+=srt.mat[k]*rsc end
				end
				local rm=Matrix.new() rm:setMatrix(unpack(cm))
				m.bones[bone]:setMatrix(rm)
			end
		end
	end
	a.dirty=true
end

function D3Anim.setAnimation(model,anim,track,loop,transitionTime,speed,onEnd)
	assert(anim and anim.bones,"Invalid animation:"..tostring(anim))
	assert(D3Anim._animatedModel[model],"Model not animatable")
	local an=D3Anim._animatedModel[model]
	local oldAnim,oldStart,oldLen,tm=nil,nil,nil,os:timer()
	if transitionTime and an.animations[track] then
		oldAnim=an.animations[track]
		oldStart=tm
		oldLen=transitionTime
	end
	an.animations[track]={
		anim=anim,tm=tm,loop=loop,
		oldAnim=oldAnim,oldStart=oldStart,oldLen=oldLen,
		speed=speed, onEnd=onEnd,
	}
end

function D3Anim._addMesh(m)
	D3Anim._animated[m]={ dirty=true, animations={} }
	D3Anim._animatedModel[m.bonesTop]={dirty=true,animations={}}
end
