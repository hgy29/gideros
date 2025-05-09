#ifndef FINDDIALOG_H
#define FINDDIALOG_H

#include <QDialog>
#include "ui_finddialog.h"

class FindDialog : public QDialog
{
	Q_OBJECT
protected:
	void hideEvent(QHideEvent * event);

public:
	FindDialog(QWidget *parent = 0);
	~FindDialog();

	QString findWhat() const;
	bool wholeWord() const;
	bool matchCase() const;
    bool regexp() const;
    bool wrap() const;

	void focusToFindWhat();
	void setSelectedText(QString s) const;

signals:
	void findNext();
	void findPrevious();

private:
	Ui::FindDialogClass ui;
};

#endif // FINDDIALOG_H
