use crate::{
    config::{DiscoveryDocument, OidcPreset, OidcPublicConfig},
    error::{OidcError, Result},
    secret::SecretValue,
};
use chrono::{DateTime, TimeZone, Utc};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode, decode_header};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

const MAX_JWKS_KEYS: usize = 100;
const MAX_CLAIM_BYTES: usize = 2048;
const CLOCK_SKEW_SECONDS: i64 = 60;

#[derive(Deserialize)]
struct JsonWebKeySet {
    keys: Vec<JsonWebKey>,
}

#[derive(Deserialize)]
struct JsonWebKey {
    kty: String,
    kid: String,
    alg: String,
    #[serde(rename = "use")]
    key_use: String,
    #[serde(default)]
    n: Option<String>,
    #[serde(default)]
    e: Option<String>,
    #[serde(default)]
    crv: Option<String>,
    #[serde(default)]
    x: Option<String>,
    #[serde(default)]
    y: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum AudienceClaim {
    One(String),
    Many(Vec<String>),
}

impl AudienceClaim {
    fn contains(&self, expected: &str) -> bool {
        match self {
            Self::One(value) => value == expected,
            Self::Many(values) => values.iter().any(|value| value == expected),
        }
    }

    fn len(&self) -> usize {
        match self {
            Self::One(_) => 1,
            Self::Many(values) => values.len(),
        }
    }
}

#[derive(Deserialize)]
struct IdTokenClaims {
    iss: String,
    sub: String,
    aud: AudienceClaim,
    exp: i64,
    iat: i64,
    #[serde(default)]
    nbf: Option<i64>,
    #[serde(default)]
    nonce: Option<String>,
    #[serde(default)]
    azp: Option<String>,
}

pub(crate) struct ValidatedIdToken {
    pub issuer: String,
    pub subject: String,
    pub authenticated_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
}

pub(crate) fn validate_id_token(
    compact_token: &SecretValue,
    jwks_json: &[u8],
    expected_nonce: &SecretValue,
    config: &OidcPublicConfig,
    discovery: &DiscoveryDocument,
    preset: &OidcPreset,
    now: DateTime<Utc>,
) -> Result<ValidatedIdToken> {
    let header = decode_header(compact_token.expose_secret())
        .map_err(|_| OidcError::InvalidProviderResponse)?;
    let kid = header.kid.ok_or(OidcError::InvalidProviderResponse)?;
    let (algorithm, algorithm_name) = match header.alg {
        Algorithm::RS256 => (Algorithm::RS256, "RS256"),
        Algorithm::ES256 => (Algorithm::ES256, "ES256"),
        _ => return Err(OidcError::InvalidProviderResponse),
    };
    if kid.is_empty()
        || kid.len() > MAX_CLAIM_BYTES
        || !preset.allowed_id_token_algorithms.contains(&algorithm_name)
        || !discovery
            .id_token_signing_alg_values_supported
            .iter()
            .any(|advertised| advertised == algorithm_name)
    {
        return Err(OidcError::InvalidProviderResponse);
    }

    let jwks: JsonWebKeySet =
        serde_json::from_slice(jwks_json).map_err(|_| OidcError::InvalidProviderResponse)?;
    if jwks.keys.is_empty() || jwks.keys.len() > MAX_JWKS_KEYS {
        return Err(OidcError::InvalidProviderResponse);
    }
    let mut matching = jwks.keys.iter().filter(|key| key.kid == kid);
    let key = matching.next().ok_or(OidcError::InvalidProviderResponse)?;
    if matching.next().is_some() || key.alg != algorithm_name || key.key_use != "sig" {
        return Err(OidcError::InvalidProviderResponse);
    }
    let decoding_key = match algorithm {
        Algorithm::RS256 if key.kty == "RSA" => DecodingKey::from_rsa_components(
            key.n.as_deref().ok_or(OidcError::InvalidProviderResponse)?,
            key.e.as_deref().ok_or(OidcError::InvalidProviderResponse)?,
        ),
        Algorithm::ES256 if key.kty == "EC" && key.crv.as_deref() == Some("P-256") => {
            DecodingKey::from_ec_components(
                key.x.as_deref().ok_or(OidcError::InvalidProviderResponse)?,
                key.y.as_deref().ok_or(OidcError::InvalidProviderResponse)?,
            )
        }
        _ => return Err(OidcError::InvalidProviderResponse),
    }
    .map_err(|_| OidcError::InvalidProviderResponse)?;
    let issuer = discovery.issuer.as_str();
    let mut validation = Validation::new(algorithm);
    validation.set_issuer(&[issuer]);
    validation.set_audience(&[config.client_id.as_str()]);
    validation.validate_exp = false;
    validation.validate_nbf = false;
    validation.set_required_spec_claims(&["iss", "sub", "aud"]);
    let claims = decode::<IdTokenClaims>(compact_token.expose_secret(), &decoding_key, &validation)
        .map_err(|_| OidcError::InvalidProviderResponse)?
        .claims;

    validate_claim_text(&claims.iss)?;
    validate_claim_text(&claims.sub)?;
    if claims.iss != issuer
        || !claims.aud.contains(&config.client_id)
        || claims.aud.len() == 0
        || claims.aud.len() > 1 && claims.azp.as_deref() != Some(config.client_id.as_str())
        || claims
            .azp
            .as_deref()
            .is_some_and(|authorized_party| authorized_party != config.client_id)
        || claims.exp <= now.timestamp() - CLOCK_SKEW_SECONDS
        || claims.iat > now.timestamp() + CLOCK_SKEW_SECONDS
        || claims
            .nbf
            .is_some_and(|not_before| not_before > now.timestamp() + CLOCK_SKEW_SECONDS)
    {
        return Err(OidcError::InvalidProviderResponse);
    }
    let nonce = claims.nonce.ok_or(OidcError::InvalidProviderResponse)?;
    validate_claim_text(&nonce)?;
    if !constant_time_equal(expected_nonce.expose_secret(), &nonce) {
        return Err(OidcError::InvalidProviderResponse);
    }
    let authenticated_at = Utc
        .timestamp_opt(claims.iat, 0)
        .single()
        .ok_or(OidcError::InvalidProviderResponse)?;
    let expires_at = Utc
        .timestamp_opt(claims.exp, 0)
        .single()
        .ok_or(OidcError::InvalidProviderResponse)?;
    if expires_at <= authenticated_at {
        return Err(OidcError::InvalidProviderResponse);
    }
    Ok(ValidatedIdToken {
        issuer: claims.iss,
        subject: claims.sub,
        authenticated_at,
        expires_at,
    })
}

fn validate_claim_text(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > MAX_CLAIM_BYTES
        || value != value.trim()
        || value.chars().any(char::is_control)
    {
        Err(OidcError::InvalidProviderResponse)
    } else {
        Ok(())
    }
}

fn constant_time_equal(expected: &str, actual: &str) -> bool {
    let expected_digest = Sha256::digest(expected.as_bytes());
    let actual_digest = Sha256::digest(actual.as_bytes());
    bool::from(expected_digest.ct_eq(&actual_digest))
}
