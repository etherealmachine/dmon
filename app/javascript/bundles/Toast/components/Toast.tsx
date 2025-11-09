import React, { useState, useEffect } from 'react';
import { createPortal } from 'react-dom';

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

  const baseClasses = "px-4 py-3 rounded relative transition-opacity duration-500 border shadow-lg";
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
  const containerRef = React.useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Style the parent wrapper div (created by react_component) to not take up space
    if (containerRef.current && containerRef.current.parentElement) {
      const parent = containerRef.current.parentElement;
      parent.style.position = 'absolute';
      parent.style.width = '0';
      parent.style.height = '0';
      parent.style.overflow = 'visible';
    }
  }, []);

  const toastContent = (
    <div
      style={{
        position: 'fixed',
        top: '1rem',
        left: '50%',
        transform: 'translateX(-50%)',
        zIndex: 9999,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '0.75rem',
        pointerEvents: 'none'
      }}
    >
      <div
        style={{
          width: '100%',
          maxWidth: '28rem',
          padding: '0 1rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '0.75rem',
          pointerEvents: 'auto'
        }}
      >
        {notice && <ToastItem message={notice} type="notice" />}
        {alert && <ToastItem message={alert} type="alert" />}
      </div>
    </div>
  );

  return (
    <>
      <div ref={containerRef} style={{ display: 'none' }} />
      {createPortal(toastContent, document.body)}
    </>
  );
}
