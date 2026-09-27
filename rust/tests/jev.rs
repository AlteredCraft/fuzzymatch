//! Exercise JevDecider over real HTTP against a local stand-in for the TypeSafe API.
//!
//! This checks that the request body has the wire shape, that auth is sent, and that a response in
//! the documented shape parses back into a Match.
#![cfg(feature = "jev")]

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::thread;

use fuzzymatch::jev::{DISPATCH_KEY, JevError};
use fuzzymatch::{Branch, Error, JevDecider, Matcher, NONE_LABEL, Verdict, branches};
use serde_json::{Value, json};

struct Captured {
    headers: Vec<String>,
    body: Value,
}

/// Serve one request with `status` and `response`, and hand back what was sent.
fn serve_once(status: u16, response: Value) -> (String, thread::JoinHandle<Captured>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = BufReader::new(stream);
        let mut headers = Vec::new();
        loop {
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            if line.trim().is_empty() {
                break;
            }
            headers.push(line.trim().to_owned());
        }
        let length: usize = headers
            .iter()
            .find_map(|h| {
                h.to_ascii_lowercase().strip_prefix("content-length:").map(|v| v.trim().parse().unwrap())
            })
            .unwrap();
        let mut body = vec![0; length];
        reader.read_exact(&mut body).unwrap();

        let payload = response.to_string();
        write!(
            reader.get_mut(),
            "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
            payload.len()
        )
        .unwrap();
        Captured { headers, body: serde_json::from_slice(&body).unwrap() }
    });
    (url, handle)
}

fn decider(url: &str) -> JevDecider {
    let agent = ureq::Agent::config_builder().proxy(None).http_status_as_error(false).build().into();
    JevDecider::new("sk-test").unwrap().base_url(url).agent(agent)
}

branches! {
    enum Intent {
        Refund => Branch::new("wants money back").when("The message includes an order number"),
        OrderStatus => Branch::new("where is my order"),
    }
}

#[test]
fn request_carries_one_choice_and_a_noul_per_guard() {
    let (url, server) = serve_once(
        200,
        json!({
            "model": "jev-1.13.0",
            "usage": {"input_tokens": 120, "output_tokens": 0},
            "answers": {
                DISPATCH_KEY: {
                    "type": "choice",
                    "choice": "Refund",
                    "confidence": 0.91,
                    "probabilities": {"Refund": 0.93, "OrderStatus": 0.04, NONE_LABEL: 0.03},
                },
                "guard__Refund": {"type": "noul", "noul": 0.88},
            },
        }),
    );
    let support = Matcher::builder("What is the customer asking for?")
        .none_description("none")
        .build(decider(&url).model("jev-1.13.0"))
        .unwrap();

    let m = support.classify("I was charged twice for order #4411").unwrap();

    let Captured { headers, body } = server.join().unwrap();
    assert!(headers.iter().any(|h| h.eq_ignore_ascii_case("authorization: Bearer sk-test")));
    assert!(headers[0].starts_with("POST /v1/systemone "));
    assert_eq!(
        body,
        json!({
            "state": "I was charged twice for order #4411",
            "model": "jev-1.13.0",
            "questions": {
                DISPATCH_KEY: {
                    "type": "choice",
                    "instructions": "What is the customer asking for?",
                    "criteria": {"Refund": "wants money back", "OrderStatus": "where is my order", NONE_LABEL: "none"},
                },
                "guard__Refund": {"type": "noul", "instructions": "The message includes an order number"},
            },
        })
    );
    // Question order is part of the wire shape: the dispatch question first, then guards.
    let keys: Vec<_> = body["questions"].as_object().unwrap().keys().cloned().collect();
    assert_eq!(keys, [DISPATCH_KEY, "guard__Refund"]);

    assert_eq!(m.verdict, Verdict::Matched(Intent::Refund));
    assert_eq!((m.confidence, m.guard), (0.91, Some(0.88)));
    assert_eq!(m.ranked()[2], (None, 0.03));
    assert_eq!(m.model.as_deref(), Some("jev-1.13.0"));
}

#[test]
fn sends_the_moving_alias_when_no_model_is_pinned() {
    let (url, server) = serve_once(
        200,
        json!({"model": "jev-1.13.0", "answers": {
            DISPATCH_KEY: {"type": "choice", "choice": "OrderStatus", "confidence": 0.97, "probabilities": {}},
            "guard__Refund": {"type": "noul", "noul": 0.1},
        }}),
    );
    let m = Matcher::new("?", decider(&url)).unwrap().classify("where's my stuff").unwrap();
    assert_eq!(m.verdict, Verdict::Matched(Intent::OrderStatus));
    assert_eq!(server.join().unwrap().body["model"], "jev-latest");
}

#[test]
fn http_errors_surface_with_the_server_message() {
    let (url, server) = serve_once(401, json!({"error": "invalid api key"}));
    let error = Matcher::<Intent, _>::new("?", decider(&url)).unwrap().classify("x").unwrap_err();
    server.join().unwrap();

    let Error::Decider(source) = error else { panic!("expected a decider error, got {error:?}") };
    match source.downcast_ref::<JevError>() {
        Some(JevError::Status { status: 401, body }) => assert!(body.contains("invalid api key")),
        other => panic!("expected an HTTP 401, got {other:?}"),
    }
}
