(() => {
  const canvas = document.querySelector('#hdr-light');
  const scene = canvas.closest('.scene');
  const hdrDisplay = matchMedia('(dynamic-range: high)');
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
  let device, context, pipeline, uniforms, bindGroup;
  let frame = 0;
  let last = null;
  let phase = 0;
  let visible = true;
  let busy = false;
  let failed = false;

  const code = `
    struct Frame { phase: f32, aspect: f32, still: f32, padding: f32 };
    @group(0) @binding(0) var<uniform> frame: Frame;
    struct Varying { @builtin(position) position: vec4f, @location(0) uv: vec2f };
    @vertex fn vertex(@builtin(vertex_index) index: u32) -> Varying {
      let corners = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
      var out: Varying;
      out.position = vec4f(corners[index], 0.0, 1.0);
      out.uv = corners[index] * vec2f(0.5, -0.5) + vec2f(0.5);
      return out;
    }
    @fragment fn fragment(in: Varying) -> @location(0) vec4f {
      let uv = in.uv;
      let p = (uv - vec2f(0.5, 0.24)) * vec2f(frame.aspect, 1.0);
      let q = abs(p) - vec2f(frame.aspect * 0.421 - 0.20, 0.434 - 0.20);
      let distance = abs(length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - 0.20);
      let travel = uv.x * 6.283185 - frame.phase;
      let colors = vec3f(0.78) + 0.22 * cos(travel + vec3f(0.0, 2.0, 4.0));
      let head = 0.5 + 0.5 * cos(travel);
      let glint = pow(head, 4.0);
      let core = (1.0 - smoothstep(0.008, 0.044, distance)) * (0.68 + 0.30 * glint);
      let haze = (1.0 - smoothstep(0.024, 0.19, distance)) * (0.04 + 0.12 * head);
      let a = max(core, haze);
      let intensity = 1.30 + glint * (1.0 - 0.5 * frame.still);
      return vec4f(colors * intensity * core + colors * haze * 0.55, a);
    }
  `;

  function wanted() {
    return hdrDisplay.matches && visible && !document.hidden && !failed;
  }
  function stop() {
    cancelAnimationFrame(frame);
    frame = 0;
    last = null;
  }
  function fallBack() {
    failed = true;
    stop();
    canvas.hidden = true;
    canvas.removeAttribute('data-hdr');
  }
  function draw(now) {
    frame = 0;
    if (!wanted() || !pipeline) return;
    const moving = scene.dataset.playing === 'true' && !reducedMotion.matches;
    if (moving && last !== null) phase = (phase + Math.min(50, now - last) / 700) % (2 * Math.PI);
    last = moving ? now : null;
    const aspect = (canvas.clientWidth || canvas.width) / (canvas.clientHeight || canvas.height);
    device.queue.writeBuffer(uniforms, 0, new Float32Array([phase, aspect, reducedMotion.matches ? 1 : 0, 0]));
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginRenderPass({ colorAttachments: [{
      view: context.getCurrentTexture().createView(),
      clearValue: [0, 0, 0, 0], loadOp: 'clear', storeOp: 'store'
    }] });
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.draw(3);
    pass.end();
    device.queue.submit([encoder.finish()]);
    if (moving) frame = requestAnimationFrame(render);
  }
  function render(now) {
    try { draw(now); } catch { fallBack(); }
  }
  async function refresh() {
    stop();
    canvas.hidden = !wanted() || !pipeline;
    if (!wanted() || busy) return;
    if (!pipeline) {
      if (!navigator.gpu) return;
      busy = true;
      try {
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) throw new Error('GPU unavailable');
        device = await adapter.requestDevice();
        device.lost.then(fallBack);
        context = canvas.getContext('webgpu');
        device.pushErrorScope('validation');
        context.configure({ device, format: 'rgba16float', alphaMode: 'premultiplied',
          toneMapping: { mode: 'extended' } });
        if (await device.popErrorScope()) throw new Error('Extended canvas unavailable');
        if (context.getConfiguration && context.getConfiguration().toneMapping?.mode !== 'extended') {
          throw new Error('Extended canvas unsupported');
        }
        const module = device.createShaderModule({ code });
        pipeline = await device.createRenderPipelineAsync({
          layout: 'auto', vertex: { module, entryPoint: 'vertex' },
          fragment: { module, entryPoint: 'fragment', targets: [{ format: 'rgba16float' }] }
        });
        uniforms = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
        bindGroup = device.createBindGroup({ layout: pipeline.getBindGroupLayout(0),
          entries: [{ binding: 0, resource: { buffer: uniforms } }] });
        canvas.dataset.hdr = 'extended';
      } catch { fallBack(); }
      finally { busy = false; }
    }
    if (pipeline && wanted()) {
      canvas.hidden = false;
      frame = requestAnimationFrame(render);
    }
  }
  new MutationObserver(refresh).observe(scene, { attributes: true, attributeFilter: ['data-playing'] });
  new MutationObserver(() => { if (pipeline && wanted() && !frame) frame = requestAnimationFrame(render); })
    .observe(canvas.parentElement, { attributes: true, attributeFilter: ['data-open'] });
  if ('ResizeObserver' in window) {
    new ResizeObserver(() => { if (pipeline && wanted() && !frame) frame = requestAnimationFrame(render); }).observe(canvas);
  }
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; refresh(); }).observe(scene);
  }
  hdrDisplay.addEventListener('change', refresh);
  reducedMotion.addEventListener('change', refresh);
  document.addEventListener('visibilitychange', refresh);
  refresh();
})();
