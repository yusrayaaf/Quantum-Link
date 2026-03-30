import { useEffect, lazy, Suspense } from "react";
import { BrowserRouter, Routes, Route, Navigate, useLocation } from "react-router-dom";
import { useStore } from "./store";
import { SocketProvider } from "./context/SocketContext";
import Sidebar from "./components/Sidebar";
import Toast from "./components/Toast";
import "./App.css";

// Lazy-loaded pages
const AuthPage = lazy(() => import("./pages/AuthPage"));
const ChatPage = lazy(() => import("./pages/ChatPage"));
const VoicePage = lazy(() => import("./pages/VoicePage"));
const VideoPage = lazy(() => import("./pages/VideoPage"));
const ProfilePage = lazy(() => import("./pages/ProfilePage"));
const CreatorPanel = lazy(() => import("./pages/CreatorPanel"));

function PageLoader() {
  return (
    <div className="page-loader">
      <div className="loader-ring" />
    </div>
  );
}

function PrivateRoute({ children }) {
  const token = useStore((s) => s.token);
  return token ? children : <Navigate to="/auth" replace />;
}

function PublicRoute({ children }) {
  const token = useStore((s) => s.token);
  return !token ? children : <Navigate to="/chat" replace />;
}

function CreatorRoute({ children }) {
  const { token, user } = useStore((s) => ({ token: s.token, user: s.user }));
  if (!token) return <Navigate to="/auth" replace />;
  if (user?.role !== "creator" && user?.role !== "admin") return <Navigate to="/chat" replace />;
  return children;
}

function AppLayout({ children }) {
  const location = useLocation();
  const isAuth = location.pathname === "/auth";

  return (
    <div className={`app-shell ${isAuth ? "auth-shell" : ""}`}>
      {!isAuth && <Sidebar />}
      <main className="app-main">
        <Suspense fallback={<PageLoader />}>{children}</Suspense>
      </main>
      <Toast />
    </div>
  );
}

function AppRoutes() {
  return (
    <AppLayout>
      <Routes>
        <Route path="/" element={<Navigate to="/chat" replace />} />
        <Route
          path="/auth"
          element={
            <PublicRoute>
              <AuthPage />
            </PublicRoute>
          }
        />
        <Route
          path="/chat"
          element={
            <PrivateRoute>
              <ChatPage />
            </PrivateRoute>
          }
        />
        <Route
          path="/chat/:roomId"
          element={
            <PrivateRoute>
              <ChatPage />
            </PrivateRoute>
          }
        />
        <Route
          path="/voice"
          element={
            <PrivateRoute>
              <VoicePage />
            </PrivateRoute>
          }
        />
        <Route
          path="/voice/:roomId"
          element={
            <PrivateRoute>
              <VoicePage />
            </PrivateRoute>
          }
        />
        <Route
          path="/video"
          element={
            <PrivateRoute>
              <VideoPage />
            </PrivateRoute>
          }
        />
        <Route
          path="/video/:roomId"
          element={
            <PrivateRoute>
              <VideoPage />
            </PrivateRoute>
          }
        />
        <Route
          path="/profile"
          element={
            <PrivateRoute>
              <ProfilePage />
            </PrivateRoute>
          }
        />
        <Route
          path="/creator"
          element={
            <CreatorRoute>
              <CreatorPanel />
            </CreatorRoute>
          }
        />
        <Route
          path="/creator/:tab"
          element={
            <CreatorRoute>
              <CreatorPanel />
            </CreatorRoute>
          }
        />
        <Route path="*" element={<Navigate to="/chat" replace />} />
      </Routes>
    </AppLayout>
  );
}

export default function App() {
  const initAuth = useStore((s) => s.initAuth);

  useEffect(() => {
    initAuth();
  }, [initAuth]);

  return (
    <BrowserRouter>
      <SocketProvider>
        <AppRoutes />
      </SocketProvider>
    </BrowserRouter>
  );
}
