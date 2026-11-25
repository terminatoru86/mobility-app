"""Minimal shapefile + dbf reader with LCC (NAD83 state plane) inverse. No deps."""
import struct, math, re

def read_dbf(path):
    b = open(path, 'rb').read()
    n, hl, rl = struct.unpack('<xxxxIHH', b[:12])
    fields = []
    p = 32
    while b[p] != 0x0D:
        name = b[p:p+11].split(b'\0')[0].decode('latin1')
        t = chr(b[p+11]); ln = b[p+16]
        fields.append((name, t, ln)); p += 32
    recs = []
    for i in range(n):
        r = b[hl + i*rl: hl + (i+1)*rl]
        o = 1; d = {}
        for name, t, ln in fields:
            v = r[o:o+ln].decode('latin1', 'replace').strip(); o += ln
            if t in 'NF':
                try: v = float(v) if v else None
                except: v = None
            d[name] = v
        recs.append(d)
    return recs

def read_shp(path):
    b = open(path, 'rb').read()
    p = 100; out = []
    while p < len(b):
        num, clen = struct.unpack('>ii', b[p:p+8]); p += 8
        rec = b[p:p+clen*2]; p += clen*2
        st = struct.unpack('<i', rec[:4])[0]
        if st == 0: out.append(None); continue
        if st in (1, 11, 21):
            x, y = struct.unpack('<dd', rec[4:20]); out.append(('pt', [(x, y)]))
        elif st in (3, 5, 13, 15, 23, 25):
            npart, npt = struct.unpack('<ii', rec[36:44])
            parts = list(struct.unpack('<%di' % npart, rec[44:44+4*npart]))
            q = 44 + 4*npart
            pts = [struct.unpack('<dd', rec[q+16*i:q+16*i+16]) for i in range(npt)]
            parts.append(npt)
            out.append(('line', [pts[parts[i]:parts[i+1]] for i in range(npart)]))
        elif st in (8, 18, 28):
            npt = struct.unpack('<i', rec[36:40])[0]
            out.append(('pt', [struct.unpack('<dd', rec[40+16*i:56+16*i]) for i in range(npt)]))
        else:
            out.append(None)
    return out

class LCC:
    def __init__(self, prj):
        def P(k):
            return float(re.search(r'PARAMETER\["%s",([-\d.eE]+)\]' % k, prj).group(1))
        a = 6378137.0; f = 1/298.257222101; e = math.sqrt(2*f - f*f)
        unit = float(re.findall(r'UNIT\["[^"]*",([\d.eE]+)\]', prj.split('PROJECTION')[1])[0])
        self.unit = unit
        p1, p2, p0 = map(math.radians, (P('Standard_Parallel_1'), P('Standard_Parallel_2'), P('Latitude_Of_Origin')))
        self.l0 = math.radians(P('Central_Meridian'))
        self.fe = P('False_Easting')*unit; self.fn = P('False_Northing')*unit
        m = lambda p: math.cos(p)/math.sqrt(1 - e*e*math.sin(p)**2)
        t = lambda p: math.tan(math.pi/4 - p/2)/((1 - e*math.sin(p))/(1 + e*math.sin(p)))**(e/2)
        self.n = (math.log(m(p1)) - math.log(m(p2)))/(math.log(t(p1)) - math.log(t(p2)))
        self.F = m(p1)/(self.n*t(p1)**self.n)
        self.a = a; self.e = e
        self.r0 = a*self.F*t(p0)**self.n
    def inv(self, x, y):
        x = x*self.unit - self.fe; y = self.r0 - (y*self.unit - self.fn)
        n = self.n
        r = math.copysign(math.hypot(x, y), n)
        th = math.atan2(x, y) if n > 0 else math.atan2(-x, -y)
        t = (r/(self.a*self.F))**(1/n)
        phi = math.pi/2 - 2*math.atan(t)
        for _ in range(10):
            es = self.e*math.sin(phi)
            phi = math.pi/2 - 2*math.atan(t*((1 - es)/(1 + es))**(self.e/2))
        return math.degrees(th/n + self.l0), math.degrees(phi)

class TM:
    def __init__(self, prj):
        def P(k):
            return float(re.search(r'PARAMETER\["%s",([-\d.eE]+)\]' % k, prj).group(1))
        self.unit = float(re.findall(r'UNIT\["[^"]*",([\d.eE]+)\]', prj.split('PROJECTION')[1])[0])
        self.a = 6378137.0; f = 1/298.257222101; self.e2 = 2*f - f*f
        self.k0 = P('Scale_Factor'); self.l0 = math.radians(P('Central_Meridian'))
        self.fe = P('False_Easting')*self.unit; self.fn = P('False_Northing')*self.unit
        self.p0 = math.radians(P('Latitude_Of_Origin'))
    def M(self, p):
        e2 = self.e2; a = self.a
        return a*((1-e2/4-3*e2**2/64-5*e2**3/256)*p-(3*e2/8+3*e2**2/32+45*e2**3/1024)*math.sin(2*p)
                  +(15*e2**2/256+45*e2**3/1024)*math.sin(4*p)-(35*e2**3/3072)*math.sin(6*p))
    def inv(self, x, y):
        a, e2, k0 = self.a, self.e2, self.k0
        x = x*self.unit - self.fe; y = y*self.unit - self.fn
        M = self.M(self.p0) + y/k0
        mu = M/(a*(1-e2/4-3*e2**2/64-5*e2**3/256))
        e1 = (1-math.sqrt(1-e2))/(1+math.sqrt(1-e2))
        p1 = mu+(3*e1/2-27*e1**3/32)*math.sin(2*mu)+(21*e1**2/16-55*e1**4/32)*math.sin(4*mu)+(151*e1**3/96)*math.sin(6*mu)+(1097*e1**4/512)*math.sin(8*mu)
        ep2 = e2/(1-e2); C1 = ep2*math.cos(p1)**2; T1 = math.tan(p1)**2
        N1 = a/math.sqrt(1-e2*math.sin(p1)**2); R1 = a*(1-e2)/(1-e2*math.sin(p1)**2)**1.5
        D = x/(N1*k0)
        lat = p1-(N1*math.tan(p1)/R1)*(D**2/2-(5+3*T1+10*C1-4*C1**2-9*ep2)*D**4/24+(61+90*T1+298*C1+45*T1**2-252*ep2-3*C1**2)*D**6/720)
        lon = self.l0+(D-(1+2*T1+C1)*D**3/6+(5-2*C1+28*T1-3*C1**2+8*ep2+24*T1**2)*D**5/120)/math.cos(p1)
        return math.degrees(lon), math.degrees(lat)

def load(base):
    prj = open(base + '.prj').read()
    geoms = read_shp(base + '.shp'); recs = read_dbf(base + '.dbf')
    tr = (lambda x, y: (x, y)) if 'PROJCS' not in prj else (TM(prj).inv if 'Transverse_Mercator' in prj else LCC(prj).inv)
    out = []
    for g, r in zip(geoms, recs):
        if not g: continue
        kind, parts = g
        if kind == 'pt':
            out.append((r, 'pt', [tr(*p) for p in parts]))
        else:
            out.append((r, 'line', [[tr(*p) for p in part] for part in parts]))
    return out
