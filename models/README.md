# Modelos del motor de recomendaciones (ONNX)

Esta carpeta contiene el/los modelo(s) ONNX que consume el `OnnxRecommendationEngine` de Cauce
(`Recommendations:EngineKind = "Onnx"`).

## `dummy_v0.0.1.onnx` — modelo PLACEHOLDER

**No tiene validez clínica.** Es una regresión logística con pesos aleatorios (semilla fija),
entrenada sobre datos sintéticos, generada por `backend/tools/generate_dummy_onnx.py`. Su único
propósito es demostrar la infraestructura ONNX **end-to-end**: carga del modelo, inferencia con
`Microsoft.ML.OnnxRuntime`, y trazabilidad a una `model_versions` (`is_dummy = true`).

## Cómo lo reemplaza Mirian (sin tocar código C#)

1. Dejar el archivo `.onnx` real en esta carpeta (mismo path) **o** apuntar
   `Recommendations:OnnxModelPath` al nuevo archivo.
2. Ajustar el nombre de versión si corresponde (el motor deriva la versión activa del descriptor;
   ver `RecommendationsModelVersionsSeeder`).
3. Poner `Recommendations:EngineKind = "Onnx"` en la configuración del entorno.

No se requiere recompilar ni cambiar código: el motor resuelve el path hacia arriba desde el
directorio de ejecución buscando `infrastructure/models/<archivo>` y, si no lo encuentra, cae de
forma silenciosa al motor de regla (`FodmapRuleRecommendationEngine`).

## Contrato de entrada/salida esperado

- **Entrada** `input`: tensor `float32` de forma `[N, 5]` — 5 features del contexto del paciente
  (en el dummy: edad, IMC, años desde el diagnóstico, fumador 0/1, consume alcohol 0/1).
- **Salidas**: `label` (`int64 [N]`) y probabilidades (`float32 [N, 3]`), con las clases
  `0 = suggest`, `1 = reduce`, `2 = avoid`.

## Deuda técnica (coordinar con Mirian, post-defensa)

- Reemplazo por el modelo real (swap del binario).
- **Equivalencia numérica PyTorch↔ONNX `< 0.001` NO es verificable con el dummy** (pesos aleatorios);
  se valida cuando exista el modelo real.
- Semántica definitiva de las 5 features de entrada y del post-procesamiento por alimento (hoy el
  motor modula la tendencia del paciente por el nivel FODMAP de cada alimento candidato).

## Regenerar el dummy

```bash
pip install scikit-learn skl2onnx numpy onnx
python backend/tools/generate_dummy_onnx.py
```
