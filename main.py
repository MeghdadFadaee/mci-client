from os import getenv
from gui import LabelWindow
from mci import MCIInternetClient
from dotenv import load_dotenv

load_dotenv()

client = MCIInternetClient(".env")


class App(LabelWindow):

    def text_schedule(self):
        try:

            unused_labels = []
            unused_amounts = client.get_unused_amounts_bytes()

            for val in unused_amounts:
                unused_labels.append(f"{val / (1024 ** 2):10.2f} MB")

            self.set_label_text("\n".join(unused_labels))
        except Exception as exception:
            self.set_label_text(f"Error: {str(exception)}")
        return '-'


if __name__ == "__main__":
    INTERVAL = int(getenv('PULL_INTERVAL_SECONDS')) * 1_000

    app = App()
    app.set_label_font('IRANSansWeb')
    app.set_interval(INTERVAL)
    app.mainloop()
