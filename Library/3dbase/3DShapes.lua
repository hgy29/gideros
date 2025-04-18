local Mesh3D=Core.class(Mesh,function() return true end)
Mesh3D.MODE_TEXTURE=1
Mesh3D.MODE_LIGHTING=2 --ie normals
Mesh3D.MODE_BUMP=4
Mesh3D.MODE_SHADOW=8
Mesh3D.MODE_ANIMATED=16
Mesh3D.MODE_INSTANCED=32
Mesh3D.MODE_COLORED=64
Mesh3D.MODE_VOXEL=128
Mesh3D.MODE_OCCLUSION=256
Mesh3D.MODE_DEPTHMASK=512
Mesh3D.MODE_BRICKS=1024
Mesh3D.MODE_FOG=2048

function Mesh3D:init()
	self.mode=0
end

function Mesh3D:updateMode(set,clear)
	local nm=(self.mode|(set or 0))&~(clear or 0)
	if nm~=self.mode then
		self.mode=nm
		if (nm&Mesh3D.MODE_LIGHTING)>0 then
			local tc=""
			if (nm&Mesh3D.MODE_TEXTURE)>0 then tc=tc.."t" end
			if (nm&Mesh3D.MODE_SHADOW)>0 then tc=tc.."s" end
			if (nm&Mesh3D.MODE_BUMP)>0 then tc=tc.."n" end
			if (nm&Mesh3D.MODE_ANIMATED)>0 then tc=tc.."a" end
			if (nm&Mesh3D.MODE_INSTANCED)>0 then tc=tc.."i" end
			if (nm&Mesh3D.MODE_COLORED)>0 then tc=tc.."c" end
			if (nm&Mesh3D.MODE_VOXEL)>0 then tc=tc.."v" end
			if (nm&Mesh3D.MODE_OCCLUSION)>0 then tc=tc.."o" end
			if (nm&Mesh3D.MODE_DEPTHMASK)>0 then tc=tc.."d" end
			if (nm&Mesh3D.MODE_BRICKS)>0 then tc=tc.."b" end
			if (nm&Mesh3D.MODE_FOG)>0 then tc=tc.."f" end
			Lighting.setSpriteMode(self,tc)
		end
	end
end

function Mesh3D:setInstanceCount(n)
	self._im1,self._im2,self._im3,self._im4=
		self._im1 or {}, self._im2 or {},self._im3 or {},self._im4 or {}
	self._icount=n
end

function Mesh3D:setInstanceMatrix(i,m)
	local is=i*4-3
	if m then
		local mm={m:getMatrix()}
		self._im1[is],self._im1[is+1],self._im1[is+2],self._im1[is+3]=mm[1],mm[2],mm[3],mm[4]
		self._im2[is],self._im2[is+1],self._im2[is+2],self._im2[is+3]=mm[5],mm[6],mm[7],mm[8]
		self._im3[is],self._im3[is+1],self._im3[is+2],self._im3[is+3]=mm[9],mm[10],mm[11],mm[12]
		self._im4[is],self._im4[is+1],self._im4[is+2],self._im4[is+3]=mm[13],mm[14],mm[15],mm[16]
	else
		for i=3,0,-1 do
			self._im1[is+i]=nil
			self._im2[is+i]=nil
			self._im3[is+i]=nil
			self._im4[is+i]=nil
		end
	end
end

function Mesh3D:updateInstances()
	local icc=self._icount*4
	for i=1,icc do
		self._im1[i]=self._im1[i] or 0
		self._im2[i]=self._im2[i] or 0
		self._im3[i]=self._im3[i] or 0
		self._im4[i]=self._im4[i] or 0
	end
	if self._icount==0 then 
		self:updateMode(0,Mesh3D.MODE_INSTANCED)
	else 
		self:updateMode(Mesh3D.MODE_INSTANCED,0)
		self:setGenericArray(6,Shader.DFLOAT,4,self._icount,self._im1)
		self:setGenericArray(7,Shader.DFLOAT,4,self._icount,self._im2)
		self:setGenericArray(8,Shader.DFLOAT,4,self._icount,self._im3)
		self:setGenericArray(9,Shader.DFLOAT,4,self._icount,self._im4)
	end
	Mesh.setInstanceCount(self,self._icount)
end

function Mesh3D:setLocalMatrix(m)
	self:setShaderConstant("InstanceMatrix",Shader.CMATRIX,1,m:getMatrix())
end

-- ***************************************
--Unit Cube
local Box=Core.class(Mesh3D)
function Box:init(w,h,d)
	w=w or 1 h=h or 1 d=d or 1
	if not Box.ia then
		Box.ia={
			1,2,3,1,3,4,
			5,6,7,5,7,8,
			9,10,11,9,11,12,
			13,14,15,13,15,16,
			17,18,19,17,19,20,
			21,22,23,21,23,24,
		}
		Box.na={
			0,0,-1,0,0,-1,0,0,-1,0,0,-1,
			0,0,1,0,0,1,0,0,1,0,0,1,
			0,-1,0,0,-1,0,0,-1,0,0,-1,0,
			0,1,0,0,1,0,0,1,0,0,1,0,
			-1,0,0,-1,0,0,-1,0,0,-1,0,0,
			1,0,0,1,0,0,1,0,0,1,0,0,
		}
	end
	self._va={
		-w,h,-d, w,h,-d, w,-h,-d, -w,-h,-d,
		w,h,d, -w,h,d, -w,-h,d, w,-h,d,
		-w,-h,-d, w,-h,-d, w,-h,d, -w,-h,d,
		-w,h,d, w,h,d, w,h,-d, -w,h,-d,
		-w,h,d, -w,h,-d, -w,-h,-d, -w,-h,d,
		w,h,-d, w,h,d, w,-h,d, w,-h,-d,
	}
	self:setGenericArray(3,Shader.DFLOAT,3,24,Box.na)
	self:setVertexArray(self._va)
	self:setIndexArray(Box.ia)
	self._va=Box.va self._ia=Box.ia
	self.dims={w=w,h=h,d=d}
end
function Box:mapTexture(texture,sw,sh)
	self:setTexture(texture)
	if texture then
		local tw,th=texture:getWidth()*(sw or 1),texture:getHeight()*(sh or 1)
		self:setTextureCoordinateArray{
			0,0,tw,0,tw,th,0,th,
			0,0,tw,0,tw,th,0,th,
			0,0,tw,0,tw,th,0,th,
			0,0,tw,0,tw,th,0,th,
			0,0,tw,0,tw,th,0,th,
			0,0,tw,0,tw,th,0,th,
		}
		self:updateMode(Mesh3D.MODE_TEXTURE,0)
	else
		self:updateMode(0,Mesh3D.MODE_TEXTURE)
	end
end
function Box:getCollisionShape()
	if not self._r3dshape then
		self._r3dshape=r3d.BoxShape.new(self.dims.w,self.dims.h,self.dims.d)
	end
	return self._r3dshape
end

-- ***************************************
--Unit Sphere
local Sphere=Core.class(Mesh3D)
function Sphere:init(steps,radius)
	local va,ia={},{}
--	local rs=(2*3.141592654)/steps
	local rs=(2*math.pi)/steps
	local idx,ni=4,1
	--Vertices
	va[1]=0 va[2]=radius va[3]=0
	for iy=1,(steps//2)-1 do
		local y=math.cos(iy*rs)*radius
		local r=math.sin(iy*rs)*radius
		for ix=0,steps do
			local x=r*math.cos(ix*rs)
			local z=r*math.sin(ix*rs)
			va[idx]=x idx+=1
			va[idx]=y idx+=1
			va[idx]=z idx+=1
		end
	end
	va[idx]=0 va[idx+1]=-radius va[idx+2]=0
	local lvi=idx//3+1
	--Indices
	--a) top and bottom fans
	for i=1,steps do
		ia[ni]=1 ni+=1 ia[ni]=i+1 ni+=1 ia[ni]=i+2 ni+=1
		ia[ni]=lvi ni+=1 ia[ni]=lvi-i ni+=1 ia[ni]=lvi-i-1 ni+=1
	end
	--b) quads
	for iy=1,(steps//2)-2 do
		local b=1+(steps+1)*(iy-1)
		for ix=1,steps do
			ia[ni]=b+ix ni+=1 ia[ni]=b+ix+1 ni+=1 ia[ni]=b+ix+steps+1 ni+=1
			ia[ni]=b+ix+steps+1 ni+=1 ia[ni]=b+ix+1 ni+=1 ia[ni]=b+ix+steps+2 ni+=1
		end
	end
	self:setGenericArray(3,Shader.DFLOAT,3,lvi,va)
	self:setVertexArray(va)
	self:setIndexArray(ia)
	self._steps=steps
	self.radius=radius
	self._va=va self._ia=ia
end
function Sphere:mapTexture(texture)
	self:setTexture(texture)
	if texture then
		local tw,th=texture:getWidth(),texture:getHeight()
		local va={}
		local i=3
		--TexCoords
		va[1]=tw/2 va[2]=0
		for iy=1,(self._steps//2)-1 do
			local y=th*(iy*2/self._steps)
			for ix=0,self._steps do
				local x=tw*(ix/self._steps)
				va[i]=x i+=1
				va[i]=y i+=1
			end
		end
		va[i]=tw/2	va[i+1]=th
		self:setTextureCoordinateArray(va)
		self:updateMode(Mesh3D.MODE_TEXTURE,0)
	else
		self:updateMode(0,Mesh3D.MODE_TEXTURE)
	end
end
function Sphere:getCollisionShape()
	if not self._r3dshape then
		self._r3dshape=r3d.SphereShape.new(self.radius)
	end
	return self._r3dshape
end

-- ***************************************
--Unit Cylinder along Y axis
local Cylinder=Core.class(Mesh3D)
function Cylinder:init(steps,r,h)
	local va,ia,na={},{},{}
--	local rs=(2*3.141592654)/steps
	local rs=(2*math.pi)/steps
	local idx,ni=7,1
	r=r or 1
	h=h or 1
	self.radius=r
	self.height=h
	--Vertices/Normals
	va[1]=0 va[2]=h va[3]=0 --TOP
	va[4]=0	va[5]=-h va[6]=0 --BOTTOM
	na[1]=0 na[2]=1 na[3]=0 --TOP
	na[4]=0	na[5]=-1 na[6]=0 --BOTTOM
	for ix=0,steps do
		local x=math.cos(ix*rs)*r
		local z=-math.sin(ix*rs)*r
		--EDGE-TOP
		va[idx]=x na[idx]=0 idx+=1
		va[idx]=h na[idx]=1 idx+=1
		va[idx]=z na[idx]=0 idx+=1
		--EDGE-TOPEXT
		va[idx]=x na[idx]=x idx+=1
		va[idx]=h na[idx]=0 idx+=1
		va[idx]=z na[idx]=z idx+=1
		--EDGE-BOTTOMEXT
		va[idx]=x na[idx]=x idx+=1
		va[idx]=-h na[idx]=0 idx+=1
		va[idx]=z na[idx]=z idx+=1
		--EDGE-BOTTOM
		va[idx]=x na[idx]=0 idx+=1
		va[idx]=-h na[idx]=-1 idx+=1
		va[idx]=z na[idx]=0 idx+=1
	end
	--Indices
	for i=3,steps*4-1,4 do
		--For rendering, take care of normals
		ia[ni]=1 ni+=1 ia[ni]=i ni+=1 ia[ni]=i+4 ni+=1 --TOP-PART
		ia[ni]=2 ni+=1 ia[ni]=i+3 ni+=1 ia[ni]=i+7 ni+=1 --BOTTOM-PART
		ia[ni]=i+1 ni+=1 ia[ni]=i+2 ni+=1 ia[ni]=i+5 ni+=1 --EDGE-TRI1
		ia[ni]=i+2 ni+=1 ia[ni]=i+6 ni+=1 ia[ni]=i+5 ni+=1 --EDFE-TRI2
	end
	self:setGenericArray(3,Shader.DFLOAT,3,#na//3,na)
	self:setVertexArray(va)
	self:setIndexArray(ia)
	self._steps=steps
	self._va=va self._ia=ia
	self.dims={r=r,h=h}
end
function Cylinder:mapTexture(texture)
	self:setTexture(texture)
	if texture then
		local tw,th=texture:getWidth(),texture:getHeight()
		local va={}
		local i=5
		--TexCoords
		local twh,thh=tw/2,th/2
		va[1]=twh va[2]=0
		va[3]=twh va[4]=th
		for xi=0,self._steps do
			local x=tw*(xi/self._steps)
			va[i]=x i+=1
			va[i]=0 i+=1
			va[i]=x i+=1
			va[i]=0 i+=1
			va[i]=x i+=1
			va[i]=th i+=1
			va[i]=x i+=1
			va[i]=th i+=1
		end
		self:setTextureCoordinateArray(va)
		self:updateMode(Mesh3D.MODE_TEXTURE,0)
	else
		self:updateMode(0,Mesh3D.MODE_TEXTURE)
	end
end
function Cylinder:getCollisionShape()
	if not self._r3dshape then
		--For collision, ensure closed/CCW shape
		local steps=self._steps
		local ca,fa={},{}
		local nc,nf=1,1
		for i=3,steps*4-1,4 do ca[nc]=i+1 nc+=1 end --TOP SURFACE
		fa[nf]=steps nf+=1
		for i=3,steps*4-1,4 do
			ca[nc]=i+1 nc+=1 ca[nc]=i+2 nc+=1 
			ca[nc]=i+6 nc+=1 ca[nc]=i+5 nc+=1 
			fa[nf]=4 nf+=1
		end
		ca[nc-2]=5 ca[nc-1]=4
		for i=steps*4-1,3,-4 do ca[nc]=i+2 nc+=1 end
		fa[nf]=steps nf+=1
		self._r3dshape=r3d.ConvexMeshShape.new(self._va,ca,fa)
	end
	return self._r3dshape
end

-- ***************************************
local Group3D=Core.class(Mesh,function() return true end)
function Group3D:updateMode(set,clear)
      for _,v in pairs(self.objs) do
              v:updateMode(set,clear)
      end
end

-- ***************************************
D3=D3 or {}
D3.Group=Group3D
D3.Mesh=Mesh3D
D3.Cube=Box
D3.Sphere=Sphere
D3.Cylinder=Cylinder

-- ***************************************
D3.checkCCW=function(v,i,f)
	local fi=1
	for fn=1,#f do
		local s=""
		for l=fi,fi+f[fn]-1 do
			local ii=i[l]*3-2
			local ax,ay,az=v[ii],v[ii+1],v[ii+2]
			s=s..string.format("%d:[%f,%f,%f] ",i[l],ax,ay,az)
		end
		fi+=f[fn]
		--print(fn,f[fn],s)
	end
end
