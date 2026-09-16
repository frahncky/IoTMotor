import { Component } from "react";

const S = {
  wrap: {
    background: "#1a2023",
    border: "1px solid #2b3538",
    borderRadius: 10,
    padding: "32px 24px",
    margin: "48px auto",
    maxWidth: 600,
    color: "#edf1ef",
    fontFamily: "'Inter', 'Segoe UI', sans-serif",
  },
  title: { color: "#d17a76", fontWeight: 700, fontSize: 16, marginBottom: 12 },
  pre: { color: "#9aa5a4", fontSize: 12, whiteSpace: "pre-wrap", wordBreak: "break-word" },
  btn: {
    marginTop: 16,
    background: "none",
    border: "1px solid #2b3538",
    color: "#9aa5a4",
    borderRadius: 6,
    padding: "8px 20px",
    cursor: "pointer",
    fontSize: 13,
  },
};

export class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("[ErrorBoundary]", error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        <div style={S.wrap}>
          <div style={S.title}>Algo deu errado</div>
          <pre style={S.pre}>{this.state.error.message}</pre>
          <button style={S.btn} onClick={() => this.setState({ error: null })}>
            Tentar novamente
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
