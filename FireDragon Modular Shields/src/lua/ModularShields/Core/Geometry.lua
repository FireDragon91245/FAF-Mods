local function Copy(p) return {p[1],p[2],p[3]} end
local function Entry(a,b,c,r,ground)
    local x,y,z=a[1]-c[1],ground and 0 or a[2]-c[2],a[3]-c[3]
    local dx,dy,dz=b[1]-a[1],ground and 0 or b[2]-a[2],b[3]-a[3]
    local cc=x*x+y*y+z*z-r*r
    if cc<=0 then return nil end
    local aa=dx*dx+dy*dy+dz*dz
    if aa<0.000001 then return nil end
    local bb=2*(x*dx+y*dy+z*dz)
    local disc=bb*bb-4*aa*cc
    if disc<=0 then return nil end
    local t=(-bb-math.sqrt(disc))/(2*aa)
    if t>=0 and t<=1 then return t end
end
local function Point(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
local function Normal(p,c)
    local x,y,z=p[1]-c[1],p[2]-c[2],p[3]-c[3]
    local n=math.sqrt(x*x+y*y+z*z)
    if n<.001 then return {1,0,0} end
    return {x/n,y/n,z/n}
end
local function Reflect(v,n,minOutward)
    local dot=v[1]*n[1]+v[2]*n[2]+v[3]*n[3]
    local change=math.max(minOutward or 0,math.abs(dot))-dot
    return {v[1]+n[1]*change,v[2]+n[2]*change,v[3]+n[3]*change}
end
Export={Copy=Copy,Entry=Entry,Point=Point,Normal=Normal,Reflect=Reflect}
return Export
