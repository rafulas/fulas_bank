use tauri::menu::{AboutMetadata, Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::Manager;

pub fn build(app: &tauri::AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let pkg = app.package_info().clone();

    let prefs = MenuItem::with_id(app, "preferences", "Preferencias…", true, Some("Cmd+,"))?;
    let switch = MenuItem::with_id(app, "switch_server", "Cambiar dirección…", true, Some("Cmd+Shift+O"))?;
    let updates = MenuItem::with_id(app, "check_updates", "Buscar actualizaciones…", true, None::<&str>)?;
    let app_menu = Submenu::with_items(
        app,
        &pkg.name,
        true,
        &[
            &PredefinedMenuItem::about(app, Some(&pkg.name), Some(AboutMetadata::default()))?,
            &updates,
            &PredefinedMenuItem::separator(app)?,
            &prefs,
            &switch,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::hide(app, None)?,
            &PredefinedMenuItem::hide_others(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::quit(app, None)?,
        ],
    )?;

    let file_menu = Submenu::with_items(
        app,
        "Archivo",
        true,
        &[&PredefinedMenuItem::close_window(app, None)?],
    )?;

    let edit_menu = Submenu::with_items(
        app,
        "Edición",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;

    let reload = MenuItem::with_id(app, "reload", "Recargar", true, Some("Cmd+R"))?;
    let view_menu = Submenu::with_items(app, "Ver", true, &[&reload])?;

    let window_menu = Submenu::with_items(
        app,
        "Ventana",
        true,
        &[
            &PredefinedMenuItem::minimize(app, None)?,
            &PredefinedMenuItem::maximize(app, None)?,
        ],
    )?;

    Menu::with_items(app, &[&app_menu, &file_menu, &edit_menu, &view_menu, &window_menu])
}

pub fn on_event(app: &tauri::AppHandle, id: &str) {
    match id {
        // Handled entirely in Rust: showing the prefs window does not depend on
        // the remote page's IPC being available, so it works on any page.
        "preferences" | "switch_server" => {
            let prefs = app.get_webview_window("prefs");
            if let Some(main) = app.get_webview_window("main") {
                let _ = main.eval(&format!(
                    "console.log('[sure] menu {} -> prefs window present: {}')",
                    id,
                    prefs.is_some()
                ));
            }
            if let Some(w) = prefs {
                let _ = w.show();
                let _ = w.set_focus();
                let _ = w.unminimize();
            }
        }
        // Fulas Bank: the Mac install (mac/ in the repository) keeps its
        // scripts in ~/FulasBank. aviso.sh --ahora checks GitHub for a newer
        // version and answers in a native window, with «Actualizar ahora»
        // when there is one.
        "check_updates" => check_updates(app),
        "reload" => {
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.eval("window.location.reload()");
            }
        }
        _ => {}
    }
}

fn check_updates(app: &tauri::AppHandle) {
    let script = std::env::var("HOME")
        .map(|home| std::path::Path::new(&home).join("FulasBank").join("aviso.sh"))
        .ok()
        .filter(|path| path.exists());
    let started = match script.map(|path| std::process::Command::new("/bin/bash").arg(path).arg("--ahora").spawn()) {
        Some(Ok(mut child)) => {
            // Collect its exit in the background so no finished process lingers.
            std::thread::spawn(move || {
                let _ = child.wait();
            });
            true
        }
        _ => false,
    };
    if !started {
        if let Some(w) = app.get_webview_window("main") {
            let _ = w.eval(
                "alert('No encuentro la instalación de Fulas Bank en la carpeta FulasBank de tu usuario. Vuelve a lanzar el instalador (mac/LEEME.md).')",
            );
        }
    }
}
