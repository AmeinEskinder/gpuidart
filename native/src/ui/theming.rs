use super::*;
use crate::protocol::ThemeMode;
use gpui_kit::component::{Theme, ThemeConfigColors, ThemeRegistry};
use std::rc::Rc;

impl DartView {
    pub(super) fn reconcile_theme(&mut self, cx: &mut Context<Self>) -> Result<(), String> {
        let spec = self.snapshot.theme.clone().unwrap_or_default();
        if self.applied_theme.as_ref() == Some(&spec) {
            return Ok(());
        }
        let colors = spec.colors()?;
        // Start from the registry, never from the previously overridden palette.
        let registry = ThemeRegistry::global(cx);
        let mut config = match spec.mode {
            ThemeMode::Light => registry.default_light_theme().as_ref().clone(),
            ThemeMode::Dark => registry.default_dark_theme().as_ref().clone(),
        };
        for (token, color) in colors {
            set_override(&mut config.colors, token, format!("#{color:06X}").into());
        }
        Theme::update(cx, |theme| theme.apply_config(&Rc::new(config)));
        self.applied_theme = Some(spec);
        Ok(())
    }

    pub(super) fn inspect_theme(&self, cx: &App) -> Value {
        let colors = cx.theme().colors;
        let resolved = TOKENS
            .into_iter()
            .map(|token| {
                let rgb = resolve_color(StyleColor::Token(token), &colors).to_rgb();
                let value = ((rgb.r * 255.).round() as u32) << 16
                    | ((rgb.g * 255.).round() as u32) << 8
                    | (rgb.b * 255.).round() as u32;
                (token.name().to_string(), json!(format!("#{value:06X}")))
            })
            .collect::<serde_json::Map<_, _>>();
        json!({"descriptor":self.applied_theme, "resolved":resolved})
    }
}

const TOKENS: [ThemeToken; 16] = [
    ThemeToken::Background,
    ThemeToken::Foreground,
    ThemeToken::Primary,
    ThemeToken::PrimaryForeground,
    ThemeToken::Secondary,
    ThemeToken::SecondaryForeground,
    ThemeToken::Muted,
    ThemeToken::MutedForeground,
    ThemeToken::Accent,
    ThemeToken::AccentForeground,
    ThemeToken::Danger,
    ThemeToken::DangerForeground,
    ThemeToken::Border,
    ThemeToken::Success,
    ThemeToken::Warning,
    ThemeToken::Info,
];

fn set_override(colors: &mut ThemeConfigColors, token: ThemeToken, value: SharedString) {
    match token {
        ThemeToken::Background => colors.background = Some(value),
        ThemeToken::Foreground => colors.foreground = Some(value),
        ThemeToken::Primary => {
            colors.primary = Some(value);
            colors.primary_hover = None;
            colors.primary_active = None;
        }
        ThemeToken::PrimaryForeground => colors.primary_foreground = Some(value),
        ThemeToken::Secondary => {
            colors.secondary = Some(value);
            colors.secondary_hover = None;
            colors.secondary_active = None;
        }
        ThemeToken::SecondaryForeground => colors.secondary_foreground = Some(value),
        ThemeToken::Muted => colors.muted = Some(value),
        ThemeToken::MutedForeground => colors.muted_foreground = Some(value),
        ThemeToken::Accent => colors.accent = Some(value),
        ThemeToken::AccentForeground => colors.accent_foreground = Some(value),
        ThemeToken::Danger => {
            colors.danger = Some(value);
            colors.danger_hover = None;
            colors.danger_active = None;
        }
        ThemeToken::DangerForeground => colors.danger_foreground = Some(value),
        ThemeToken::Border => colors.border = Some(value),
        ThemeToken::Success => {
            colors.success = Some(value);
            colors.success_hover = None;
            colors.success_active = None;
        }
        ThemeToken::Warning => {
            colors.warning = Some(value);
            colors.warning_hover = None;
            colors.warning_active = None;
        }
        ThemeToken::Info => {
            colors.info = Some(value);
            colors.info_hover = None;
            colors.info_active = None;
        }
    }
}
