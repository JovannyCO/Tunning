# Tunning: terminal reproducible para Ubuntu, WSL2 y Cloud Shell

[![Licencia MIT](https://img.shields.io/badge/licencia-MIT-blue)](LICENSE) · [Comprobaciones locales](docs/USO.md#comprobaciones-y-documentación)

[![Tunning: tu entorno listo para trabajar. Explora el proyecto de Jovanny Medina Cifuentes, Analista de Sistemas y Desarrollador de Software.](assets/tunning-jovanny-medina-cifuentes-header.png)](#de-una-terminal-nueva-a-un-entorno-de-trabajo)

**Una terminal nueva debería acercarte a tu trabajo, no devolverte a la configuración inicial.**

Tunning reúne la preparación del entorno, una terminal con apariencia Material MD3 y comandos para sincronizar proyectos y actualizar herramientas. Está pensado para retomar el trabajo en Ubuntu, WSL2 y Google Cloud Shell con una configuración reproducible.

Soy **Jovanny Medina Cifuentes**, **Analista de Sistemas** y **Desarrollador de Software**. Este repositorio muestra cómo convierto una necesidad cotidiana en una solución que se puede instalar, revisar y comprobar.

[Preparar mi terminal](#instalar-tunning) · [Ver cómo trabajo](#jovanny-medina-cifuentes-dos-roles-un-mismo-proyecto) · [Consultar la guía](docs/USO.md) · [Hablemos de tu proyecto](mailto:proyectos@Jovanny.CO)

## De una terminal nueva a un entorno de trabajo

Al cambiar de equipo o abrir un entorno en la nube, vuelven las mismas tareas: preparar el prompt, recuperar atajos, ajustar comandos y comprobar que Git funciona como esperas. Cada ajuste manual añade una oportunidad de olvidar algo.

Creé Tunning para conservar esa preparación en un repositorio público. Puedo clonarlo por HTTPS al iniciar una terminal, incluso antes de configurar SSH con GitHub, y aplicar el mismo punto de partida.

| Lo que necesitas resolver | Lo que aporta Tunning | Dónde comprobarlo |
|---|---|---|
| Volver a trabajar sin reconstruir cada ajuste | Instalación que detecta el entorno, conserva preferencias y respalda los archivos que reemplaza | [Instalador](scripts/install.py) |
| Saber dónde estás y si un comando falló | Prompt con directorio, rama Git, reloj y estado del último comando | [Prompt Bash](configs/prompt-bash.sh) |
| Publicar un proyecto sin olvidar sus submódulos | `git sync` procesa primero los hijos y después sus padres, conservando sus ramas y la política de firma | [Sincronización Git](scripts/git-sync.sh) |
| Mantener las herramientas al día | `devup` ofrece actualización completa o ligera y resume los errores | [Actualizador](scripts/devup.sh) |

Puedes inspeccionar los cambios con `--dry-run`, preparar una instalación aislada y revisar la sintaxis y los enlaces con [el verificador local](scripts/verify.py).

## Instalar Tunning

En Ubuntu 26.04, con **Git y Python 3** disponibles:

```bash
git clone https://github.com/JovannyCO/Tunning.git
cd Tunning
bash setup.sh
source ~/.bashrc
```

El instalador detecta Ubuntu/WSL2 o Cloud Shell. En Ubuntu/WSL2 utiliza el prompt Bash; Cloud Shell conserva su variante sin iconos Nerd Font. Los comandos quedan instalados en tu usuario y siguen funcionando aunque muevas el checkout.

Si ya tienes las dependencias, puedes inspeccionar los cambios antes de aplicarlos:

```bash
bash setup.sh --no-packages --dry-run
bash setup.sh --no-packages
```

Para Windows Terminal, fuentes, extras, Starship y respaldos, consulta la [guía de instalación y apariencia](docs/USO.md#apariencia-y-teclado).

La [matriz de compatibilidad](docs/COMPATIBILIDAD.md) distingue los ajustes automáticos de los pasos del emulador y del editor. Si usas un agente de IA, comienza por [AGENTS.md](AGENTS.md). Para comprobar la instalación dentro de Google Cloud Shell, copia [promptTMP.md](promptTMP.md) en tu agente.

### Tres acciones de uso diario

```bash
git sync "Describir el cambio realizado"
devup -l
devup -y
```

`git sync` confirma, integra, comprueba en local y publica la rama de trabajo de cada repositorio. `devup -l` actualiza las CLI contempladas; `devup -y` incluye la actualización del sistema. Revisa la [guía de Git sync](docs/USO.md#git-sync) y la [guía de devup](docs/USO.md#devup) antes del primer uso.

Para revisar cambios individuales, `git syncPR "mensaje"` publica y prepara PR
con sus issues tras las pruebas locales; `git syncPRmerge` exige criterios,
pruebas y auditoría independiente
vigentes antes de fusionar, de hijos a padres. Consulta la [política y guía de
PR](docs/GIT-PR.md). Los tres alias comparten el motor recursivo y conservan
la firma y rama de trabajo de cada repositorio.

**Antes de publicar:** configura la autenticación y la firma que use tu repositorio. `git sync` agrega todos los archivos no ignorados; mantén credenciales y claves privadas fuera del control de versiones. Los detalles están en la [guía de uso](docs/USO.md#git-sync).

## Jovanny Medina Cifuentes: dos roles, un mismo proyecto

### Analista de Sistemas

Mi trabajo comienza por entender qué necesita la persona que usa el sistema y qué debe conservarse al cambiarlo. En Tunning, eso se traduce en distinguir los entornos, respetar la configuración existente y definir qué ocurre cuando falta una rama o falla una operación.

Puedes revisar esas decisiones en la [guía de uso](docs/USO.md) y en el [diagnóstico de Ubuntu y WSL2](VALIDACION-Ubuntu-26-WSL2.md).

### Desarrollador de Software

Convierto esas decisiones en herramientas que se pueden ejecutar y mantener. En Tunning, el instalador guarda respaldos, los comandos tienen una implementación común y el verificador local comprueba sintaxis y enlaces.

Puedes revisar el [instalador](scripts/install.py), el [comando Git sync](scripts/git-sync.sh) y el [verificador local](scripts/verify.py).

**¿Buscas un Analista de Sistemas o un Desarrollador de Software para tu equipo?** [Conversemos sobre lo que necesitas resolver](mailto:proyectos@Jovanny.CO). También puedes conocer otros proyectos en [mi perfil de GitHub](https://github.com/JovannyCO) y conectar conmigo en [LinkedIn](https://www.linkedin.com/in/jovannyCO/).

## Preguntas frecuentes

### ¿Necesito SSH para instalar Tunning?

Puedes clonar este repositorio público por HTTPS sin configurar SSH ni iniciar sesión en GitHub. Para publicar tus propios cambios sí necesitas autenticarte en el remoto y disponer de la firma que hayas configurado.

### ¿Se conservan mi identidad Git y mis preferencias?

El instalador conserva la identidad, la firma, el prompt y los extras elegidos, y guarda respaldos de los archivos que reemplaza. Una reinstalación sin cambios no duplica bloques de configuración. Para cambiar de selección usa `--prompt`, `--extras` o `--no-extras`: [guía de instalación](docs/USO.md#instalar-o-actualizar).

### ¿Git sync también publica los submódulos?

Sí. Descubre los submódulos recursivamente, valida el árbol y publica primero los hijos. Después publica las referencias de los padres. Si falla un hijo, sus padres no se publican. Un HEAD separado necesita una rama configurada inequívoca: [comportamiento y preferencias](docs/USO.md#git-sync).

### ¿Git sync abre o fusiona pull requests?

`git sync` publica las ramas de trabajo. `git syncPR` prepara issues y PR en borrador tras pasar las pruebas locales. `git syncPRmerge` permite una fusión solicitada explícitamente cuando se cumplen la política, los criterios y la auditoría independiente: [guía de PR](docs/GIT-PR.md).

### ¿Cómo puedo comprobar el proyecto antes de instalarlo?

Puedes leer el [código del instalador](scripts/install.py), usar `--dry-run` o preparar una [instalación aislada](docs/USO.md#instalar-o-actualizar). Para comprobar sintaxis y enlaces locales:

```bash
python3 scripts/verify.py
```

Las comprobaciones se ejecutan en la terminal antes de publicar.

## Licencia y contribuciones

Tunning se distribuye bajo [MIT](LICENSE), con atribución a **Jovanny Medina Cifuentes**. Puedes usarlo, modificarlo y compartirlo conservando los avisos de autor y licencia. Las dependencias externas mantienen sus propias licencias. Consulta [cómo contribuir](CONTRIBUTING.md) y [cómo informar de un problema de seguridad](SECURITY.md).

## Hablemos de tu proyecto

Si necesitas preparar mejor el entorno de tu equipo, automatizar una tarea o conectar herramientas que hoy trabajan por separado, escríbeme a **[proyectos@Jovanny.CO](mailto:proyectos@Jovanny.CO)**. Cuéntame qué necesitas resolver, con qué trabajas hoy y qué quieres mejorar.

[![¿Tu equipo pierde tiempo preparando herramientas? Hablemos de tu proyecto con Jovanny Medina Cifuentes, Analista de Sistemas y Desarrollador de Software. Correo: proyectos@Jovanny.CO.](assets/tunning-jovanny-medina-cifuentes-footer.png)](mailto:proyectos@Jovanny.CO)
