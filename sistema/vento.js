// Funções independentes da interface: horários UTC e vento meteorológico de origem.
const Wind = (() => {
  const radians = Math.PI / 180;
  function bearing(a, b) {
    const p = a[0] * radians, q = b[0] * radians, d = (b[1] - a[1]) * radians;
    if (Math.abs(a[0]-b[0])+Math.abs(a[1]-b[1]) < 1e-9) return null;
    return (Math.atan2(Math.sin(d)*Math.cos(q), Math.cos(p)*Math.sin(q)-Math.sin(p)*Math.cos(q)*Math.cos(d))/radians+360)%360;
  }
  function vector(speed, from) {
    return [-speed*Math.sin(from*radians), -speed*Math.cos(from*radians)];
  }
  function sample(data, lat, lon, time) {
    if (!Number.isFinite(time) || !data.locations?.length) return null;
    const location = data.locations.reduce((best, item) => {
      const distance = (item.requested[0]-lat)**2 + ((item.requested[1]-lon)*Math.cos(lat*radians))**2;
      return !best || distance < best.distance ? {item,distance} : best;
    }, null).item;
    const h = location.hourly, times = h.time;
    if (time < times[0] || time > times.at(-1)) return null;
    let hi = times.findIndex(t=>t>=time), lo = Math.max(0,hi-1);
    if (times[hi] === time) lo = hi;
    const values = [h.wind_speed_10m[lo],h.wind_speed_10m[hi],h.wind_direction_10m[lo],h.wind_direction_10m[hi]];
    if (!values.every(Number.isFinite) || values[0]<0 || values[1]<0) return null;
    const f = lo === hi ? 0 : (time-times[lo])/(times[hi]-times[lo]);
    const a = vector(values[0],values[2]), b = vector(values[1],values[3]);
    const east = a[0]+(b[0]-a[0])*f, north = a[1]+(b[1]-a[1])*f;
    const speed = Math.hypot(east,north), to = (Math.atan2(east,north)/radians+360)%360;
    return {speed,to,from:(to+180)%360,east,north,location,lo:times[lo],hi:times[hi]};
  }
  function relative(wind, heading) {
    if (!wind) return {label:'Sem dados',color:'#b3b3be',head:null,cross:null};
    if (wind.speed<1) return {label:'Vento fraco',color:'#b3b3be',head:0,cross:0};
    if (!Number.isFinite(heading)) return {label:'Direção do trecho indefinida',color:'#b3b3be',head:null,cross:null};
    const head = -(wind.east*Math.sin(heading*radians)+wind.north*Math.cos(heading*radians));
    const cross = wind.east*Math.cos(heading*radians)-wind.north*Math.sin(heading*radians);
    const ratio = head/wind.speed;
    return {label:ratio>=0.5?'Contra':ratio<=-0.5?'A favor':'Lateral',color:ratio>=0.5?'#f29477':ratio<=-0.5?'#79cca6':'#a2b4ff',head,cross};
  }
  return {bearing,sample,relative};
})();
