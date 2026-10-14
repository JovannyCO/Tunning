# Presentación y descubrimiento de Tunning en GitHub

[Volver a la portada](../README.md)

La portada presenta Tunning como un caso de trabajo de **Jovanny Medina Cifuentes**, con sus dos roles: **Analista de Sistemas** y **Desarrollador de Software**. Cada afirmación sobre el proyecto tiene enlaces al código, a las pruebas o a la guía de uso. El contacto profesional coincide con el publicado en [su perfil de GitHub](https://github.com/JovannyCO).

## Qué se aplica en este repositorio

| Objetivo | Implementación |
|---|---|
| SEO: describir el proyecto y facilitar su descubrimiento | Título descriptivo, descripción del repositorio, topics pertinentes, encabezados jerárquicos y enlaces con nombres claros |
| AEO: facilitar respuestas a preguntas reales | Preguntas frecuentes sobre HTTPS, configuración, submódulos, pull requests y validación, con respuestas directas y enlaces a la guía |
| GEO: ofrecer información comprobable para búsquedas y respuestas generativas | Autor y roles explícitos, contexto del problema, alcance del proyecto y referencias al código y las pruebas |
| Accesibilidad y uso de imágenes | Archivos locales con nombres descriptivos, texto alternativo y CTA disponibles también como texto |

Los enlaces a archivos e imágenes son relativos para que GitHub los resuelva según la rama consultada. La página principal muestra `main`; los cambios de una rama de trabajo aparecen allí después de integrar su PR.

## Metadatos de GitHub

La descripción y los topics se guardan en GitHub, fuera de los archivos versionados. Esta es la configuración usada para acompañar la portada:

**Descripción:** Tunning: terminal reproducible para Ubuntu, WSL2 y Google Cloud Shell, con Material MD3, git sync recursivo y devup. Caso de trabajo de Jovanny Medina Cifuentes, Analista de Sistemas y Desarrollador de Software.

**Topics:** `ubuntu`, `wsl2`, `google-cloud-shell`, `bash`, `python`, `terminal`, `developer-experience`, `dotfiles`, `material-design-3`, `git`, `git-submodules`, `automation`.

Si cambia el alcance del proyecto, actualiza tanto estos metadatos como el README. Mantén el nombre profesional, los dos roles y los datos de contacto consistentes; evita repetir palabras clave sin aportar información.

La [licencia MIT](../LICENSE), la [guía de contribución](../CONTRIBUTING.md), la [política de seguridad](../SECURITY.md) y el [verificador local](../scripts/verify.py) aportan condiciones de reutilización y comprobaciones reproducibles. La [guía de uso](USO.md#comprobaciones-y-documentación) explica las comprobaciones locales; la [guía de PR](GIT-PR.md) detalla la evidencia y la auditoría independiente necesarias para publicar y fusionar.

## Alcance de la optimización

GitHub controla el HTML de la página, sus metadatos y las reglas de rastreo de `github.com`. Un README no permite configurar esas propiedades como lo haría un sitio propio. Por eso este cambio no añade etiquetas `meta`, scripts JSON-LD, `robots.txt`, sitemaps ni archivos `llms.txt` para intentar controlar la página del repositorio.

La estructura del contenido ayuda a entender el proyecto. No garantiza indexación, posiciones en buscadores ni citas o recomendaciones de asistentes de IA. Google mantiene los fundamentos de SEO para sus funciones generativas y desaconseja los supuestos atajos específicos de AEO/GEO.

Referencias oficiales:

- [GitHub: contenido del README y enlaces relativos](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes).
- [GitHub: clasificar el repositorio con topics](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics).
- [Google Search: optimización para funciones de IA generativa](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide).
- [Google Search: buenas prácticas para imágenes](https://developers.google.com/search/docs/appearance/google-images).

Los [prompts y los archivos de las imágenes](../assets/README.md) quedan versionados para mantener la presentación.
