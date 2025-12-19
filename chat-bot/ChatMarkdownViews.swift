//
//  ChatMarkdownViews.swift
//  chat-bot
//
//  Shared Markdown rendering views for the chat UI.
//

import SwiftUI
import WebKit

/// Simple markdown text renderer using `AttributedString`.
/// This does not support LaTeX math but is useful for lightweight markdown.
struct MarkdownText: View {
    let text: String
    
    var body: some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

/// A WKWebView-based renderer that supports full Markdown (via markdown-it)
/// and LaTeX-style math (via MathJax).
struct MathMarkdownWebView: UIViewRepresentable {
    let text: String
    @Binding var dynamicHeight: CGFloat
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.configuration.userContentController.add(context.coordinator, name: "contentHeight")
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Normalize common LaTeX math delimiters so they survive markdown-it parsing.
        // `\( ... \)` -> `$...$`, `\[ ... \]` -> `$$...$$`.
        let normalizedText = text
            .replacingOccurrences(of: #"\("#, with: "$")
            .replacingOccurrences(of: #"\)"#, with: "$")
            .replacingOccurrences(of: #"\["#, with: "$$")
            .replacingOccurrences(of: #"\]"#, with: "$$")
        
        let data = Data(normalizedText.utf8)
        let base64 = data.base64EncodedString()
        
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0\" />
          <style>
            :root {
              color-scheme: light;
            }
            body {
              margin: 0;
              padding: 0;
              background-color: transparent;
              color: #000000;
              font-family: -apple-system, -apple-system-body, system-ui, -apple-system-headline;
              font-size: 16px;
              line-height: 1.4;
            }
            #content {
              padding: 0;
              word-wrap: break-word;
              overflow-wrap: break-word;
            }
            h1, h2, h3, h4, h5, h6 {
              font-weight: 600;
              margin: 0.4em 0 0.2em 0;
            }
            p {
              margin: 0.2em 0;
            }
            ul, ol {
              margin: 0.2em 0 0.2em 1.2em;
              padding: 0;
            }
            code {
              font-family: Menlo, SFMono-Regular, ui-monospace, monospace;
              font-size: 0.9em;
              background-color: rgba(0,0,0,0.05);
              padding: 2px 4px;
              border-radius: 4px;
            }
            pre {
              font-family: Menlo, SFMono-Regular, ui-monospace, monospace;
              background-color: rgba(0,0,0,0.05);
              padding: 8px;
              border-radius: 6px;
              overflow-x: auto;
              margin: 0.4em 0;
            }
            pre code {
              background: transparent;
              padding: 0;
            }
            table {
              border-collapse: collapse;
            }
            table, th, td {
              border: 1px solid rgba(0,0,0,0.1);
            }
            th, td {
              padding: 4px 6px;
            }
            a {
              color: #007aff;
              text-decoration: none;
            }
            a:active {
              opacity: 0.7;
            }
          </style>
          <script>
            // Configure MathJax to support $...$, $$...$$, \\(...\\), and \\[...\\] syntaxes.
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
              },
              options: {
                skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code']
              }
            };
          </script>
          <script src=\"https://cdn.jsdelivr.net/npm/markdown-it@13.0.1/dist/markdown-it.min.js\"></script>
          <script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js\"></script>
        </head>
        <body>
          <div id=\"content\"></div>
          <script>
            (function() {
              function b64DecodeUnicode(str) {
                try {
                  return decodeURIComponent(escape(window.atob(str)));
                } catch (e) {
                  return '';
                }
              }
              
              const markdownBase64 = '\(base64)';
              const markdownSource = b64DecodeUnicode(markdownBase64);
              
              const md = window.markdownit({
                html: false,
                linkify: true,
                breaks: true
              });
              
              const rendered = md.render(markdownSource);
              document.getElementById('content').innerHTML = rendered;
              
              function postHeight() {
                var h = document.body.scrollHeight || document.documentElement.scrollHeight || 0;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contentHeight) {
                  window.webkit.messageHandlers.contentHeight.postMessage(h);
                }
              }
              
              if (window.MathJax && window.MathJax.typesetPromise) {
                window.MathJax.typesetPromise().then(postHeight).catch(postHeight);
              } else {
                postHeight();
              }
            })();
          </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MathMarkdownWebView
        
        init(_ parent: MathMarkdownWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "contentHeight" else { return }
            
            var newHeight: CGFloat?
            if let value = message.body as? CGFloat {
                newHeight = value
            } else if let number = message.body as? NSNumber {
                newHeight = CGFloat(number.doubleValue)
            }
            
            if let h = newHeight, h > 0, abs(h - parent.dynamicHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.dynamicHeight = h
                }
            }
        }
    }
}

/// A convenience bubble view that automatically sizes itself to fit the rendered content.
struct MathMarkdownBubbleView: View {
    let text: String
    @State private var height: CGFloat = 20
    
    var body: some View {
        MathMarkdownWebView(text: text, dynamicHeight: $height)
            // Add a small extra bottom space to avoid clipping descenders
            // or the last line of text inside the bubble.
            .frame(minHeight: height + 4, maxHeight: height + 4)
    }
}


