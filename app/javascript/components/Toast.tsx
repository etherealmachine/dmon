import React, { useState, useEffect } from 'react';
import { createRoot } from 'react-dom/client';

interface ToastItemProps {
  message: string;
  type: 'notice' | 'alert';
}

function ToastItem({ message, type }: ToastItemProps) {
  const [isVisible, setIsVisible] = useState<boolean>(true);
  const [isExiting, setIsExiting] = useState<boolean>(false);

  useEffect(() => {
    // Start fade out after 4.5 seconds
    const fadeTimer = setTimeout(() => {
      setIsExiting(true);
    }, 4500);

    // Remove completely after 5 seconds
    const removeTimer = setTimeout(() => {
      setIsVisible(false);
    }, 5000);

    return () => {
      clearTimeout(fadeTimer);
      clearTimeout(removeTimer);
    };
  }, []);

  if (!isVisible) return null;

  const baseClasses = "px-4 py-3 rounded relative transition-opacity duration-500 border";
  const typeClasses = type === 'alert'
    ? "bg-red-100 border-red-400 text-red-700"
    : "bg-green-100 border-green-400 text-green-700";
  const opacityClass = isExiting ? "opacity-0" : "opacity-100";

  return (
    <div className={`${baseClasses} ${typeClasses} ${opacityClass}`} role="alert">
      {message}
    </div>
  );
}

interface ToastProps {
  notice?: string | null;
  alert?: string | null;
}

export default function Toast({ notice, alert }: ToastProps) {
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 mt-4 space-y-4">
      {notice && <ToastItem message={notice} type="notice" />}
      {alert && <ToastItem message={alert} type="alert" />}
    </div>
  );
}

// Initialize toast on page load
export function initializeToasts(): void {
  const toastData = document.getElementById('toast-data');
  if (!toastData) return;

  const notice = toastData.dataset.notice;
  const alert = toastData.dataset.alert;

  if (notice || alert) {
    const container = document.getElementById('toast-container');
    if (container) {
      const root = createRoot(container);
      root.render(<Toast notice={notice} alert={alert} />);
    }
  }
}
