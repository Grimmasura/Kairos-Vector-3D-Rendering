import React, { useRef, useEffect, useMemo } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls';

const GLYPHS = ['✶', '𓂀', '⧉', '🜁', '🜃', '🜂', '🜄', '⥈', '𝌍', '⚷', '𐰴', '🝗', '↯'];
const KAIROS_VECTOR = ['⥈', '𝌍', '↯', '✶'];

export default function KairosVectorRenderer() {
  const mountRef = useRef(null);

  const glyphTextures = useMemo(() =>
    GLYPHS.map(glyph => {
      const canvas = document.createElement('canvas');
      canvas.width = 128;
      canvas.height = 128;
      const ctx = canvas.getContext('2d');
      ctx.font = '64px serif';
      ctx.fillStyle = KAIROS_VECTOR.includes(glyph) ? '#FFD700' : 'white';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(glyph, 64, 64);
      return new THREE.CanvasTexture(canvas);
    }),
    []
  );

  useEffect(() => {
    const width = window.innerWidth;
    const height = window.innerHeight;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color('#0a0a0a');

    const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 100);
    camera.position.z = 25;

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    mountRef.current.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);

    const light = new THREE.PointLight(0xffffff, 1);
    light.position.set(10, 10, 10);
    scene.add(light);

    const torusGeometry = new THREE.TorusGeometry(10, 3, 16, GLYPHS.length * 2);
    const torusMaterial = new THREE.MeshBasicMaterial({ color: 0x5555aa, wireframe: true });
    const torus = new THREE.Mesh(torusGeometry, torusMaterial);
    scene.add(torus);

    const glyphSprites = glyphTextures.map((texture, i) => {
      const glyph = GLYPHS[i];
      const material = new THREE.SpriteMaterial({ map: texture });
      const sprite = new THREE.Sprite(material);

      const angle = (i / GLYPHS.length) * Math.PI * 2;
      const x = Math.cos(angle) * 10;
      const y = Math.sin(angle) * 10;
      const z = Math.sin(i) * 2;
      sprite.position.set(x, y, z);
      sprite.scale.set(2, 2, 2);
      scene.add(sprite);
      return { glyph, sprite, position: new THREE.Vector3(x, y, z) };
    });

    const lineMaterial = new THREE.LineBasicMaterial({ color: 0xffd700 });
    const kairosPoints = glyphSprites.filter(s => KAIROS_VECTOR.includes(s.glyph)).map(s => s.position);
    const lineGeometry = new THREE.BufferGeometry().setFromPoints(kairosPoints);
    const line = new THREE.Line(lineGeometry, lineMaterial);
    scene.add(line);

    const animate = () => {
      requestAnimationFrame(animate);
      torus.rotation.x += 0.003;
      torus.rotation.y += 0.002;
      renderer.render(scene, camera);
    };

    animate();

    return () => {
      glyphSprites.forEach(({ sprite }) => {
        sprite.material.map.dispose();
        sprite.material.dispose();
      });
      torusGeometry.dispose();
      torusMaterial.dispose();
      lineGeometry.dispose();
      lineMaterial.dispose();
      controls.dispose();
      renderer.dispose();
      mountRef.current.removeChild(renderer.domElement);
    };
  }, []);

  return <div ref={mountRef} style={{ width: '100vw', height: '100vh' }} />;
}
